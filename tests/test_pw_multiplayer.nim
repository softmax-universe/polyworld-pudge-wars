import
  std/[sequtils, strutils],
  polyworld/relays,
  ../examples/pudge_wars/[bots, content, game, human, maps, multiplayer, replays, sim]

type Link = object
  client: RoomClient
  connection: int

proc pump(relay: Relay, links: openArray[Link], time: float64) =
  ## Exchanges relay messages through the real binary RoomClient codec.
  for pass in 0 ..< 32:
    var changed = relay.outgoing.len > 0
    let deliveries = move(relay.outgoing)
    for delivery in deliveries:
      doAssert not delivery.close
      for link in links:
        if link.connection == delivery.connection:
          link.client.accept(delivery.bytes)
    for link in links:
      if link.connection == 0:
        continue
      let outgoing = move(link.client.outgoing)
      changed = changed or outgoing.len > 0
      for bytes in outgoing:
        relay.receive(link.connection, decode(bytes), time)
    if not changed:
      return
  doAssert false, "relay did not settle"

proc pumpMatches(
    relay: Relay, links: openArray[Link], matches: openArray[NetworkMatch],
    time: float64
) =
  ## Drives the clients without graphics or external transport.
  relay.pump(links, time)
  for i, match in matches:
    if match != nil and links[i].connection != 0:
      while match.advanceNetwork():
        discard
  relay.pump(links, time)

proc beginMatch(match: NetworkMatch) =
  ## Applies the relay's BeginMatch event exactly once.
  doAssert match.client.events.len == 1
  match.start(match.client.events[0])
  match.client.events.setLen(0)

proc rejected(match: NetworkMatch, packet: RoomMessage): bool =
  ## Lets the test verify rejection leaves the simulation untouched.
  try:
    match.applyPacket(packet)
  except RoomsError:
    return true

proc sealTick(relay: Relay, time: var float64) =
  ## Advances the real relay's clock by one human-paced game tick.
  time += 1.0 / float64(NetworkTickRate)
  relay.advance(time)

echo "Checking Pudge Wars room settings and sparse offline setup"
block:
  var config = defaultConfig()
  config.teamSize = 5
  config.maxTicks = 2
  config.setDifficulty(Fair)
  doAssert parseConfig(config.encodeConfig()) == config
  doAssert config.botEvery == 8 and config.botAimNoise == 1
  for malformed in ["[]", "{}", """{"teamSize":3.0}"""]:
    var accepted = false
    try:
      discard parseConfig(malformed)
      accepted = true
    except RoomsError:
      discard
    doAssert not accepted
  var
    seats: array[MaxPudgeCount, Seat]
    sources: array[MaxPudgeCount, string]
  seats[1] = Seat(owner: 1, kind: HumanSeat, name: "Local")
  seats[9] = Seat(owner: 1, kind: BotSeat, name: "Support")
  sources[9] = BotPolicies[4][1]
  let game = newLocalGame(config, seats, 1, sources)
  doAssert game.humanSlots == @[0]
  doAssert game.world.pudges[0].lobbySeat == 1
  doAssert game.world.pudges[1].lobbySeat == 9
  doAssert game.world.pudges[0].team == WestTeam
  doAssert game.world.pudges[1].team == EastTeam
  doAssert game.heroVms[0] == nil and game.heroVms[1] != nil
  doAssert game.humanPaced and not game.networked
  game.closeBotServices()

block bufferedBotDecision:
  echo "Checking buffered ticks retain pending bot decisions until applied"
  let
    relay = Relay()
    client = RoomClient(identity: identity(), name: "Buffered owner")
    links = [Link(client: client, connection: 1)]
  var
    time = 0.0
    config = defaultConfig()
    sources: array[MaxPudgeCount, string]
  config.maxTicks = 8
  sources[5] = "a = rotToggle()"
  client.opened()
  relay.pump(links, time)
  client.send(RoomMessage(
    kind: CreateRoom, name: "Buffered commands", number: MaxPudgeCount,
    tickRate: uint32(NetworkTickRate), payload: config.encodeConfig()
  ))
  relay.pump(links, time)
  client.claimHuman(0)
  client.send(RoomMessage(
    kind: ClaimSeat, seat: 5, seatKind: BotSeat, name: "Buffered bot"
  ))
  relay.pump(links, time)
  let match = prepareNetworkMatch(client, sources)
  defer: match.close()
  client.send(match.startRequest())
  relay.pump(links, time)
  match.beginMatch()
  let bot = match.game.heroVms[1]
  doAssert bot.decisions == 1 and client.hasPendingCommand(5)
  var commands: seq[string]
  let outgoing = move(client.outgoing)
  for bytes in outgoing:
    if decode(bytes).kind == SubmitCommand:
      commands.add bytes
    else:
      client.outgoing.add bytes
  doAssert commands.len == 1
  relay.pump(links, time)
  for step in 1 .. 2:
    relay.sealTick(time)
    relay.pump(links, time)
  client.outgoing.add commands
  relay.pump(links, time)
  relay.sealTick(time)
  relay.pump(links, time)
  doAssert client.applied == 0 and client.packets.len == 3
  for tick in 1 .. 2:
    doAssert match.advanceNetwork()
    doAssert client.applied == uint32(tick)
    doAssert bot.decisions == 1,
      "A buffered bot command must block the premature second decision"
    doAssert client.hasPendingCommand(5)
    doAssert not match.game.world.pudges[1].rotOn
  doAssert match.advanceNetwork()
  doAssert client.applied == 3 and match.game.world.pudges[1].rotOn
  doAssert bot.decisions == 2,
    "The next decision may run after its earlier command is applied"
  doAssert client.hasPendingCommand(5), "The new decision remains pending"

echo "Checking private bot owners, authoritative inputs and spectator history"
let relay = Relay()
var
  links = [
    Link(client: RoomClient(identity: identity(), name: "West"), connection: 1),
    Link(client: RoomClient(identity: identity(), name: "East"), connection: 2),
    Link(client: RoomClient(identity: identity(), name: "Watcher"),
      connection: 3)
  ]
  matches: array[3, NetworkMatch]
  time = 0.0
  config = defaultConfig()
config.maxTicks = int32(NetworkTickRate + 5)
config.runePeriod = 5
for link in links:
  link.client.opened()
relay.pump(links, time)
let
  west = links[0].client
  east = links[1].client
  watcher = links[2].client
west.send(RoomMessage(
  kind: CreateRoom, name: "Pudge Wars", number: MaxPudgeCount, flag: true,
  tickRate: uint32(NetworkTickRate), payload: config.encodeConfig()
))
relay.pump(links, time)
let room = relay.rooms[0]
east.send(RoomMessage(kind: JoinRoom, room: room.id))
relay.pump(links, time)
west.claimHuman(0)
west.send(RoomMessage(
  kind: ClaimSeat, seat: 2, seatKind: BotSeat, name: "West bot"
))
east.claimHuman(6)
east.send(RoomMessage(
  kind: ClaimSeat, seat: 7, seatKind: BotSeat, name: "East bot"
))
relay.pump(links, time)
var
  westSources: array[MaxPudgeCount, string]
  eastSources: array[MaxPudgeCount, string]
westSources[2] = "a = walkTo(34, 70)\na = hookTo(88, 68)"
eastSources[7] = "a = walkTo(94, 69)\na = hookTo(36, 67)\na = rotToggle()"
westSources[7] = "INVALID REMOTE PROGRAM"
eastSources[2] = "INVALID REMOTE PROGRAM"
matches[0] = prepareNetworkMatch(west, westSources)
west.send(matches[0].startRequest())
relay.pump(links, time)
doAssert room.phase == Playing, "Guest readiness must not gate the host"
matches[1] = prepareNetworkMatch(east, eastSources)
let
  westMatch = matches[0]
  eastMatch = matches[1]
  initial = westMatch.networkHash()
doAssert initial == eastMatch.networkHash()
doAssert westMatch.humanPudgeIndex == 0 and eastMatch.humanPudgeIndex == 2
doAssert westMatch.game.humanSlots == @[0, 2]
doAssert westMatch.game.heroVms[1] != nil and westMatch.game.heroVms[3] == nil
doAssert eastMatch.game.heroVms[1] == nil and eastMatch.game.heroVms[3] != nil
doAssert west.events[0].hash == west.events[0].setupHash()
westMatch.beginMatch()
eastMatch.beginMatch()
doAssert westMatch.game.heroVms[1].decisions == 1
doAssert eastMatch.game.heroVms[3].decisions == 1
doAssert westMatch.networkHash() == initial
doAssert eastMatch.networkHash() == initial
doAssert westMatch.game.recorder.data.actions.len == 0
doAssert westMatch.game.world.pudges[1].hooksThrown == 0

let
  route = HumanIntent(slot: 0, kind: IntentWalk, a: 36, b: 58)
  ping = HumanIntent(slot: 2, kind: IntentPing, a: 98, b: 59)
doAssert westMatch.queueHuman(route)
doAssert not eastMatch.queueHuman(route)
doAssert not westMatch.queueHuman(HumanIntent(slot: 0, kind: IntentCheat))
doAssert not westMatch.queueHuman(HumanIntent(
  slot: 0, kind: IntentHookFine, a: int32.high, b: 0
))
# The minimap uses the same human command path as the arena renderer.
installGame(eastMatch.game, eastMatch.humanPudgeIndex, networked = true)
doAssert not issueMapPing(ping.a, ping.b)
doAssert eastMatch.game.humanIntents.len == 0
activeNetwork = eastMatch
doAssert issueMapPing(ping.a, ping.b)
doAssert eastMatch.game.humanIntents.len == 0
doAssert eastMatch.game.world.pings.len == 0
activeNetwork = nil
doAssert westMatch.queueChat("Ready")
doAssert westMatch.game.chatLog.len == 0
doAssert westMatch.networkHash() == initial
relay.pump(links, time)
doAssert room.pending.len >= 7
var invalid = RoomMessage(kind: TickPacket, match: room.match, tick: 1,
  seats: room.seats, commands: room.pending)
invalid.commands[^1].participant = 0
doAssert westMatch.rejected(invalid)
invalid.commands[^1] = room.pending[^1]
invalid.commands[^1].payload.add '\0'
doAssert westMatch.rejected(invalid)
doAssert westMatch.networkHash() == initial
doAssert west.applied == 0 and westMatch.game.world.tick == 0

relay.sealTick(time)
relay.pump(links, time)
doAssert westMatch.advanceNetwork()
doAssert eastMatch.advanceNetwork()
doAssert west.applied == 1 and east.applied == 1
doAssert westMatch.networkHash() == eastMatch.networkHash()
doAssert westMatch.game.world.pudges[0].hasMoveTarget
doAssert westMatch.game.world.pudges[1].hooksThrown == 1
doAssert westMatch.game.world.pudges[3].hooksThrown == 1
doAssert westMatch.game.world.pings[0].byId == 5
doAssert westMatch.game.chatLog == eastMatch.game.chatLog
doAssert westMatch.game.chatLog[0].text == "Ready"
doAssert westMatch.game.intentResults[0].accepted

echo "Checking in-flight intent retransmission and catch-up"
doAssert eastMatch.queueHuman(HumanIntent(slot: 2, kind: IntentRot))
doAssert room.pending.len == 0, "The second bot decision must still be unsent"
doAssert east.hasPendingCommand(7)
relay.disconnect(links[1].connection)
links[1].connection = 0
east.lost()
for overflow in 0 .. MaxClientCommands:
  doAssert not eastMatch.queueHuman(ping)
doAssert not eastMatch.queueChat("While disconnected")
doAssert east.outgoing.len == 0 and east.hasPendingCommand(6)
for step in 1 .. 4:
  relay.sealTick(time)
  relay.pumpMatches(links, matches, time)
doAssert west.applied == 5 and east.applied == 1
doAssert not westMatch.game.world.pudges[2].rotOn
doAssert westMatch.game.world.pudges[3].rotOn
links[1].connection = 4
east.opened()
relay.pump(links, time)
doAssert east.applied == 1 and east.hasPendingCommand(7)
# The relay received the retried command but has yet to seal its tick.
relay.disconnect(links[1].connection)
east.lost()
links[1].connection = 5
east.opened()
relay.pumpMatches(links, matches, time)
doAssert east.events.len == 0
doAssert east.applied == west.applied
doAssert westMatch.networkHash() == eastMatch.networkHash()
doAssert westMatch.game.recorder.data.actions ==
  eastMatch.game.recorder.data.actions
var retainedRot = 0
for command in room.pending:
  if command.seat == 7:
    var reader = PacketReader(data: command.payload)
    if reader.get32() == uint32(ActionRotToggle):
      inc retainedRot
doAssert retainedRot == 1, "Reconnect must retain exactly one bot decision"
relay.sealTick(time)
relay.pumpMatches(links, matches, time)
doAssert westMatch.game.world.pudges[2].rotOn, "Human input stays queued"
doAssert not westMatch.game.world.pudges[3].rotOn, "Bot toggles Rot once"

watcher.send(RoomMessage(kind: JoinRoom, room: room.id))
relay.pump(links, time)
matches[2] = prepareNetworkMatch(watcher, [])
matches[2].beginMatch()
relay.pumpMatches(links, matches, time)
doAssert watcher.applied == west.applied
doAssert matches[2].humanPudgeIndex == -1
doAssert not matches[2].queueHuman(route)
doAssert matches[2].networkHash() == westMatch.networkHash()
doAssert matches[2].game.chatLog == westMatch.game.chatLog

echo "Checking typed handoffs, vacant controllers and immutable earlier input"
doAssert westMatch.queueHuman(HumanIntent(slot: 0, kind: IntentRot))
relay.pump(links, time)
west.send(RoomMessage(kind: ClaimSeat, seat: 0, participant: east.participant,
  seatKind: BotSeat, name: "Support"))
relay.pump(links, time)
var rotated: string
rotated.put32(uint32(ActionRotToggle))
rotated.put32(0)
rotated.put32(0)
doAssert east.submit(0, rotated)
relay.pump(links, time)
west.send(RoomMessage(kind: ClaimSeat, seat: 0, participant: watcher.participant,
  seatKind: HumanSeat, name: HumanSeatName))
relay.pump(links, time)
relay.sealTick(time)
relay.pumpMatches(links, matches, time)
doAssert westMatch.humanPudgeIndex == -1
doAssert matches[2].humanPudgeIndex == 0
doAssert not westMatch.game.world.pudges[0].rotOn,
  "The relay must keep both accepted commands through multiple handoffs"
doAssert westMatch.networkHash() == matches[2].networkHash()

doAssert matches[2].queueHuman(HumanIntent(slot: 0, kind: IntentRot))
relay.pump(links, time)
watcher.send(RoomMessage(kind: LeaveRoom))
relay.pump(links, time)
matches[2].close()
matches[2] = nil
west.send(RoomMessage(kind: ClaimSeat, seat: 0, participant: east.participant,
  seatKind: BotSeat, name: "Support"))
relay.pump(links, time)
relay.sealTick(time)
relay.pumpMatches(links, matches, time)
doAssert westMatch.game.world.pudges[0].rotOn,
  "A participant's queued command survives their departure"
doAssert eastMatch.game.heroVms[0] != nil and westMatch.game.heroVms[0] == nil
doAssert eastMatch.game.humanSlots == @[2]
east.send(RoomMessage(kind: ReleaseSeat, seat: 0))
relay.pump(links, time)
relay.sealTick(time)
relay.pumpMatches(links, matches, time)
doAssert eastMatch.game.heroVms[0] == nil
doAssert westMatch.game.world.pudges.len == 4

watcher.send(RoomMessage(kind: JoinRoom, room: room.id))
relay.pump(links, time)
matches[2] = prepareNetworkMatch(watcher, [])
matches[2].beginMatch()
relay.pumpMatches(links, matches, time)
doAssert matches[2].humanPudgeIndex == -1
doAssert matches[2].networkHash() == westMatch.networkHash()
doAssert matches[2].game.recorder.data == westMatch.game.recorder.data

while west.applied + 1 < uint32(config.maxTicks):
  relay.sealTick(time)
  relay.pumpMatches(links, matches, time)
  doAssert room.phase != Desynced
relay.sealTick(time)
relay.pump(links, time)
doAssert matches[2].advanceNetwork() and matches[2].finished
for bytes in watcher.outgoing:
  doAssert decode(bytes).kind != FinishMatch
relay.pump(links, time)
doAssert room.phase == Playing, "A spectator cannot finish the relay match"
relay.pumpMatches(links, matches, time)
relay.advance(time)
relay.pump(links, time)
doAssert room.phase == Ended
doAssert relay.guest(west.participant).hashTick == uint32(NetworkTickRate)
for match in matches:
  doAssert match.finished and match.networkHash() == westMatch.networkHash()
  doAssert match.game.recorder.data == westMatch.game.recorder.data
  match.close()

echo "Checking recorded match playback"
let
  data = decodeReplay(westMatch.game.recorder.data.encodeReplay())
  playback = newGame(
    generateMap(config.seed, config.teamSize),
    config.maxTicks, true, data
  )
playback.replayPlayer = initReplayPlayer(data)
playback.historyPlayback = true
for tick in 1 .. config.maxTicks:
  playback.tickWorld(nil)
  doAssert playback.stateHash() == data.hashes[tick - 1]
doAssert playback.stateHash() == westMatch.game.stateHash()
doAssert data.actions.anyIt(it.kind == ActionTakeOver)
west.send(RoomMessage(kind: ReturnLobby))
relay.pump(links, time)
doAssert westMatch.reopenedLobby() and matches[2].reopenedLobby()

echo "Checking a private BASIC runtime failure aborts the shared match"
westSources[2] = "a = rotToggle()\nagain: goto again"
matches[0] = prepareNetworkMatch(west, westSources)
west.send(matches[0].startRequest())
relay.pump(links, time)
matches[1] = prepareNetworkMatch(east, eastSources)
try:
  matches[0].beginMatch()
  doAssert false, "A failed private bot decision must abort"
except RoomsError as error:
  doAssert error.msg == "BASIC policy for West bot failed"
  matches[0].abort(error.msg)
relay.pump(links, time)
doAssert room.phase == Desynced and east.error.contains("West bot failed")
let failureIndex = matches[0].game.world.worldIndexOfSeat(2)
doAssert matches[0].game.heroVms[failureIndex].failed
doAssert matches[0].game.recorder.data.actions.len == 0
doAssert not matches[0].game.world.pudges[failureIndex].rotOn
for i in 0 .. 1:
  matches[i].close()

releaseGame()
