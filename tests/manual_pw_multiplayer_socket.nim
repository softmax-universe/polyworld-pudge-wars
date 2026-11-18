## Run with a separately launched, isolated Polyworld gameserver on loopback.
import
  std/[os, strutils],
  windy,
  polyworld/connections,
  ../examples/pudge_wars/[multiplayer, replays, sim]

const
  West = 0
  East = 1

let
  port = parseInt(getEnv("PUDGEWARS_SOCKET_RELAY_PORT", "19953"))
  socketUrl = "ws://127.0.0.1:" & $port & "/ws"
doAssert port in 1 .. 65535

var
  peers = [
    connect(socketUrl, "West socket QA", identity()),
    connect(socketUrl, "East socket QA", identity())
  ]
  matches: array[2, NetworkMatch]

proc frame() =
  ## Uses the same Windy message pump and adaptive playback as the renderer.
  pollEvents()
  for i, connection in peers:
    connection.pump()
    let match = matches[i]
    if match != nil and match.started and not match.finished:
      match.flushSubmissions()
      var packet: RoomMessage
      while not match.finished and connection.takeTick(packet, NetworkTickRate):
        match.applyPacket(packet)
    connection.pump()
    doAssert connection.client.error.len == 0, connection.client.error
  sleep(2)

template awaitState(condition: untyped, description: string) =
  let deadline = networkTime() + 8
  while not (condition) and networkTime() < deadline:
    frame()
  doAssert condition, description

let
  westClient = peers[West].client
  eastClient = peers[East].client
awaitState(
  westClient.welcomed and eastClient.welcomed, "Socket handshake failed"
)

var config = defaultConfig()
config.teamSize = 2
config.maxTicks = int32(3 * NetworkTickRate)
config.runePeriod = 17
westClient.send(RoomMessage(
  kind: CreateRoom, name: "Pudge Wars socket QA", number: 4,
  tickRate: uint32(NetworkTickRate), payload: config.encodeConfig()
))
awaitState(westClient.snapshot.room.len > 0, "Owner did not create the room")
let room = westClient.snapshot.room
eastClient.send(RoomMessage(kind: JoinRoom, room: room))
awaitState(eastClient.snapshot.room == room, "Guest did not join the room")
westClient.claimHuman(0)
westClient.send(RoomMessage(kind: ClaimSeat, seat: 1, name: "West socket bot"))
eastClient.claimHuman(2)
eastClient.send(RoomMessage(kind: ClaimSeat, seat: 3, name: "East socket bot"))
awaitState(
  westClient.snapshot.seats[3].owner == eastClient.participant and
    eastClient.snapshot.seats[1].owner == westClient.participant and
    westClient.snapshot.revision == eastClient.snapshot.revision,
  "Clients did not agree on both human and BASIC seats"
)

let sources = [
  ["", "a = walkTo(36, 72)\na = hookTo(88, 70)", "", ""],
  ["", "", "", "a = walkTo(95, 72)\na = hookTo(36, 70)"]
]

proc prepare(index: int) =
  ## Produces a fresh local VM and proof for one retained lobby revision.
  let client = peers[index].client
  matches[index] = prepareNetworkMatch(client, sources[index])
  client.send(RoomMessage(
    kind: PreparedDuration, revision: matches[index].revision,
    hash: matches[index].networkHash(), durationTicks: uint32(config.maxTicks)
  ))

proc start() =
  ## Applies both BeginMatch events using the prepared worlds.
  awaitState(
    westClient.events.len == 1 and eastClient.events.len == 1,
    "Relay did not start the socket match"
  )
  for i, connection in peers:
    matches[i].start(connection.client.events[0])
    connection.client.events.setLen(0)

proc saw(match: NetworkMatch, pudgeId: int32, kind: uint8): bool =
  ## Finds an authoritative replay record from the designated seat.
  for action in match.game.recorder.data.actions:
    if action.pudgeId == pudgeId and action.kind == kind:
      return true

echo "Checking socket start with automatic preparation"
westClient.send(RoomMessage(kind: StartMatch))
prepare(West)
for pass in 0 ..< 5:
  frame()
doAssert westClient.snapshot.phase == Lobby
prepare(East)
doAssert matches[West].networkHash() == matches[East].networkHash()
start()
let
  westMatch = matches[West]
  eastMatch = matches[East]
  westToken = westClient.token
  firstMatch = westClient.match
doAssert westMatch.queueHuman(HumanIntent(
  slot: 0, kind: IntentWalk, a: 38, b: 42
))
doAssert eastMatch.queueHuman(HumanIntent(
  slot: 2, kind: IntentHookFine, a: 35 * FineAimScale, b: 65 * FineAimScale
))
doAssert westMatch.queueChat("Socket handshake")
awaitState(
  westClient.applied >= 5 and eastClient.applied >= 5,
  "Both clients did not start advancing relay ticks"
)
doAssert westMatch.saw(1, ActionWalkTo) and eastMatch.saw(3, ActionHookToFine)
doAssert westMatch.saw(2, ActionHookTo) and eastMatch.saw(4, ActionHookTo)
doAssert westMatch.game.chatLog[0].text == "Socket handshake"
doAssert eastMatch.game.chatLog == westMatch.game.chatLog

echo "Checking socket disconnect, retained commands and catch-up"
let disconnectedAt = westClient.applied
doAssert westMatch.queueHuman(HumanIntent(slot: 0, kind: IntentRot))
peers[West].reconnectAfter(0.30)
awaitState(
  eastClient.applied > disconnectedAt + 3 and not westClient.welcomed,
  "The connected controller stopped during its peer's disconnect"
)
awaitState(
  westClient.welcomed and westClient.applied >= disconnectedAt + 5 and
    westMatch.saw(1, ActionRotToggle),
  "Reconnecting controller did not catch up and resend its input"
)
doAssert westClient.token == westToken and westClient.events.len == 0

echo "Checking socket match agreement and rematch"
awaitState(
  westMatch.finished and eastMatch.finished and
    westClient.snapshot.phase == Ended and eastClient.snapshot.phase == Ended,
  "The socket peers did not finish together"
)
doAssert westMatch.networkHash() == eastMatch.networkHash()
doAssert westMatch.game.recorder.data == eastMatch.game.recorder.data
doAssert westMatch.game.world.pudges[0].rotOn
westClient.send(RoomMessage(kind: ReturnLobby))
awaitState(
  westMatch.reopenedLobby() and eastMatch.reopenedLobby(),
  "The owner did not reopen the room"
)
westMatch.close()
eastMatch.close()
for i in West .. East:
  prepare(i)
westClient.send(RoomMessage(kind: StartMatch))
start()
doAssert westClient.match == firstMatch + 1
awaitState(
  matches[West].finished and matches[East].finished and
    westClient.snapshot.phase == Ended and eastClient.snapshot.phase == Ended,
  "The rematch did not finish on both peers"
)
doAssert matches[West].networkHash() == matches[East].networkHash()
doAssert matches[West].game.recorder.data == matches[East].game.recorder.data
for i, connection in peers:
  matches[i].close()
  connection.close()
