import
  std/[strutils, unicode],
  polyworld/[hashes, roomclients, rooms],
  bots, content, maps, pacing, presets, replays, sim

export presets, roomclients, rooms

const
  NetworkProtocol* = 1'u32
  NetworkTickRate* = int(HumanTickRate)
  HumanSeatName* = "Human"
  MaxMatchChatBytes = 480
  MaxBotCommandsPerTurn = 64
  ActionChat = 0'u8
  ActionForIntent: array[IntentKind, uint8] = [
    IntentWalk: ActionWalkTo,
    IntentHook: ActionHookTo,
    IntentHookFine: ActionHookToFine,
    IntentGrapple: ActionGrappleTo,
    IntentGrappleFine: ActionGrappleToFine,
    IntentBuyPower: ActionBuyPower,
    IntentAttack: ActionAttackTarget,
    IntentBuy: ActionBuyUpgrade,
    IntentStop: ActionStop,
    IntentPing: ActionPing,
    IntentBlink: ActionBlinkTo,
    IntentBlinkFine: ActionBlinkToFine,
    IntentPlaceWall: ActionPlaceWall,
    IntentPlaceMine: ActionPlaceMine,
    IntentCheat: ActionCheat,
    IntentRot: ActionRotToggle,
    IntentPlaceWard: ActionPlaceWard
  ]

type
  NetworkMatch* = ref object
    client*: RoomClient
    game*: Game
    revision*: uint32
    started*, finished*: bool
    humanIndex: int
    room: string
    matchId, setupHash: uint32
    seats: seq[Seat]
    seatPlayers: array[MaxPudgeCount, int]
    decision: Game
    decisionTick: int32 = -1
  Submission = object
    action: ReplayAction
    text: string

proc identity*(): GameIdentity =
  ## Shares a room only with the same simulation and adapter versions.
  GameIdentity(
    game: ReplayGame, gameplay: uint32(ReplayGameVersion),
    protocol: NetworkProtocol
  )

proc humanSeat*(snapshot: RoomMessage, participant: uint32): int =
  ## Finds the participant's human slot, or -1 for bot-only owners and guests.
  result = -1
  for i, seat in snapshot.seats:
    if participant != 0 and seat.owner == participant and
      seat.name == HumanSeatName:
        if result >= 0:
          reject("Each participant may control only one Pudge Wars human")
        result = i

proc claimHuman*(client: RoomClient, index: int) =
  ## Moves the local human without taking another participant's slot.
  if index notin 0 ..< client.snapshot.seats.len or
    client.snapshot.seats[index].owner notin [0'u32, client.participant]:
      reject("That seat belongs to another participant")
  let old = client.snapshot.humanSeat(client.participant)
  if old >= 0 and old != index:
    client.send(RoomMessage(kind: ReleaseSeat, seat: uint32(old)))
  client.send(RoomMessage(
    kind: ClaimSeat, seat: uint32(index), name: HumanSeatName
  ))

proc buildGame(
    config: MatchConfig,
    seats: openArray[Seat],
    localHuman: int,
    sources: openArray[string],
    client: RoomClient
): Game =
  ## Packs occupied slots in bank order and loads policy bytes only locally.
  config.validate()
  if seats.len != matchPudgeCount(config.teamSize):
    reject("Pudge Wars roster does not match its team size")
  if localHuman < -1 or localHuman >= seats.len or
    (localHuman >= 0 and seats[localHuman].owner == 0):
      reject("Invalid local Pudge Wars human seat")
  let networked = client != nil
  var
    occupied: array[Team, int]
    roster: seq[ReplayPudge]
    labels: seq[string]
    humanSlots: seq[int]
  for entry in livePudgeSetup(false, config.teamSize):
    let
      i = int(entry.lobbySeat)
      seat = seats[i]
    if seat.owner == 0:
      continue
    let human =
      if networked:
        seat.name == HumanSeatName
      else:
        i == localHuman
    var label = seat.name
    if networked:
      discard client.snapshot.humanSeat(seat.owner)
      label = ""
      for participant in client.snapshot.participants:
        if participant.id == seat.owner:
          label = if human: participant.name else: seat.name
          break
      if label.len == 0:
        reject("Occupied Pudge Wars seat is missing its owner or label")
    if human:
      humanSlots.add roster.len
    elif (not networked or seat.owner == client.participant) and
      (i >= sources.len or sources[i].len == 0):
        reject("Choose a local policy for Pudge Wars seat " & $(i + 1))
    inc occupied[Team(entry.team)]
    roster.add entry
    labels.add label
  if occupied[WestTeam] == 0 or occupied[EastTeam] == 0:
    reject("Place at least one butcher on each bank")
  result = newGame(
    generateMap(config.seed, config.teamSize),
    config.maxTicks,
    false,
    ReplayData(),
    config.killGoal,
    config.runePeriod,
    roster = roster
  )
  result.networked = networked
  result.humanSlots = humanSlots
  result.humanPaced = networked or localHuman >= 0
  result.botEvery = config.botEvery
  result.botAimNoise = config.botAimNoise
  result.applySeatLabels(labels)
  try:
    for index, pudge in result.world.pudges:
      let i = int(pudge.lobbySeat)
      if index notin humanSlots and
        (not networked or seats[i].owner == client.participant):
          result.loadBotSource(index, sources[i], nil, nil)
  except CatchableError as error:
    result.closeBotServices()
    reject("Cannot load Pudge Wars policy: " & error.msg)
  result.recorder = initReplayRecorder(
    result.currentSetup(uint32(config.maxTicks))
  )

proc newLocalGame*(
    config: MatchConfig,
    seats: openArray[Seat],
    humanSeat: int,
    sources: openArray[string]
): Game =
  ## Starts an offline match with the same roster and settings as multiplayer.
  buildGame(config, seats, humanSeat, sources, nil)

proc prepareNetworkMatch*(
    client: RoomClient, sources: openArray[string]
): NetworkMatch =
  ## Prepares this room revision, including seatless replay followers.
  let
    snapshot = client.snapshot
    config = parseConfig(snapshot.payload)
    human = snapshot.humanSeat(client.participant)
  if client.identity != identity() or snapshot.room.len == 0 or
    snapshot.tickRate != uint32(NetworkTickRate):
      reject("Pudge Wars room identity or tick rate differs from this client")
  let game = buildGame(config, snapshot.seats, human, sources, client)
  var setupHash = HashySeed
  setupHash.addHashy(config)
  setupHash.addHashy(contentHash())
  setupHash.addHashy(snapshot.seats)
  setupHash.addHashy(game.seatLabels)
  result = NetworkMatch(
    client: client, game: game, room: snapshot.room, seats: snapshot.seats,
    revision: snapshot.revision, humanIndex: game.world.worldIndexOfSeat(human),
    setupHash: setupHash
  )
  for index in result.seatPlayers.mitems:
    index = -1
  for i, pudge in game.world.pudges:
    result.seatPlayers[pudge.lobbySeat] = i

proc humanPudgeIndex*(match: NetworkMatch): int =
  ## Returns the local player's packed roster index, or -1 for a spectator.
  match.humanIndex

proc networkHash*(match: NetworkMatch): uint64 =
  ## Includes static room settings as well as the evolving replay state.
  (uint64(match.setupHash) shl 32) xor match.game.stateHash()

proc reopenedLobby*(match: NetworkMatch): bool =
  ## Lets the renderer yield after the host reopens this room for a rematch.
  match != nil and match.started and
    match.client.snapshot.room == match.room and
    match.client.snapshot.phase == Lobby

proc close*(match: NetworkMatch) =
  ## Releases private policy resources when a match is discarded.
  if match != nil:
    match.game.closeBotServices()
    match.decision = nil

proc validAction(action: ReplayAction): bool =
  ## Checks command arguments before any authoritative state is changed.
  let
    a = action.first
    b = action.second
  case action.kind
  of ActionWalkTo, ActionHookTo, ActionGrappleTo, ActionBlinkTo,
    ActionPing, ActionPlaceWall, ActionPlaceMine, ActionPlaceWard:
      a in 0 ..< int32(ReplayGridTiles) and b in 0 ..< int32(ReplayGridTiles)
  of ActionHookToFine, ActionGrappleToFine, ActionBlinkToFine:
    let extent = int32(ReplayGridTiles) * FineAimScale
    a in 0 ..< extent and b in 0 ..< extent
  of ActionAttackTarget:
    a in 0 ..< FirstPudgeId + int32(MaxPudgeCount) and b == 0
  of ActionBuyUpgrade:
    a in int32(UpgradeKind.low.ord) .. int32(UpgradeKind.high.ord) and b == 0
  of ActionBuyPower:
    a in int32(ShopItem.low.ord) .. int32(ShopItem.high.ord) and b == 0
  of ActionStop, ActionRotToggle:
    a == 0 and b == 0
  else:
    false

proc encodeAction(action: ReplayAction): string =
  ## Encodes only intent; the relay seat determines the acting butcher.
  result.put32(uint32(action.kind))
  result.put32(cast[uint32](action.first))
  result.put32(cast[uint32](action.second))

proc validChat(text: string): bool =
  ## Bounds chat and keeps control characters out of the game HUD.
  if text.len notin 1 .. MaxMatchChatBytes or validateUtf8(text) >= 0:
    return false
  for ch in text:
    if ch < ' ' or ch == '\x7f':
      return false
  true

proc decodeSubmission(bytes: string): Submission =
  ## Decodes one opaque relay payload and rejects malformed variants.
  var reader = PacketReader(data: bytes)
  let kind = reader.get32()
  if kind == uint32(ActionChat):
    result.text = reader.getString(MaxMatchChatBytes)
    if not result.text.validChat():
      reject("Invalid Pudge Wars chat")
  else:
    if kind > uint32(ActionPlaceWard):
      reject("Unknown Pudge Wars command")
    result.action = ReplayAction(
      kind: uint8(kind), first: cast[int32](reader.get32()),
      second: cast[int32](reader.get32())
    )
    if not result.action.validAction():
      reject("Invalid Pudge Wars command arguments")
  if reader.cursor != bytes.len:
    reject("Trailing Pudge Wars command bytes")

proc canSubmit(match: NetworkMatch): bool =
  ## Guards new local commands against stale or completed matches.
  match.started and not match.finished and match.client.welcomed and
    match.client.match == match.matchId and
    match.client.snapshot.phase in {Playing, Waiting}

proc queueHuman*(match: NetworkMatch, intent: HumanIntent): bool =
  ## Submits a local human intent without changing the authoritative world.
  if not match.canSubmit() or match.humanIndex < 0 or
    int(intent.slot) != match.humanIndex:
      return false
  let action = ReplayAction(
    kind: ActionForIntent[intent.kind],
    first: intent.a,
    second: intent.b
  )
  if action.validAction():
    let seat = match.game.world.pudges[match.humanIndex].lobbySeat
    result = match.client.submit(uint32(seat), action.encodeAction())

proc queueChat*(match: NetworkMatch, text: string): bool =
  ## Submits an ordinary room-wide chat line from the local human seat.
  let message = strutils.strip(text)
  if not match.canSubmit() or match.humanIndex < 0 or not message.validChat():
    return false
  var bytes: string
  bytes.put32(uint32(ActionChat))
  bytes.putString(message)
  let seat = match.game.world.pudges[match.humanIndex].lobbySeat
  match.client.submit(uint32(seat), bytes)

proc flushSubmissions*(match: NetworkMatch) =
  ## Runs each locally owned bot once at the confirmed live edge.
  let
    game = match.game
    client = match.client
    tick = game.world.tick + 1
  if not match.canSubmit() or client.snapshot.flag or
    client.applied < client.serverTick or
    match.decisionTick == tick:
      return
  match.decisionTick = tick
  var
    ready: bool
    readySeats: array[MaxPudgeCount, bool]
  for i, vm in game.heroVms:
    if vm != nil and not vm.failed and game.world.pudges[i].state != Dying and
      (tick + int32(i)) mod game.botEvery == 0 and
      not client.hasPendingCommand(uint32(game.world.pudges[i].lobbySeat)):
        readySeats[i] = true
        ready = true
  if not ready:
    return
  if match.decision == nil:
    match.decision = Game(
      world: game.world.clone(), map: game.map, networked: true,
      heroVms: newSeq[HeroVm](game.heroVms.len), humanSlots: game.humanSlots,
      botEvery: game.botEvery, botAimNoise: game.botAimNoise,
      botSpeech: game.botSpeech,
      recorder: initReplayRecorder(game.recorder.data.header.setup)
    )
  else:
    match.decision.world.restore(game.world)
  let decision = match.decision
  decision.world.tick = tick
  decision.recorder.data.actions.setLen(0)
  for i, vm in game.heroVms:
    decision.heroVms[i] = if readySeats[i]: vm else: nil
  # BASIC actions retain their immediate results on this scratch world.
  decision.runBotDecisions(includeHumans = false)
  game.botSpeech = decision.botSpeech
  for i, vm in decision.heroVms:
    if vm != nil and vm.failed:
      # The runtime already logged the private diagnostic locally.
      reject("BASIC policy for " & game.seatLabels[i] & " failed")
  if decision.recordingError.len > 0:
    reject(decision.recordingError)
  var submitted: array[MaxPudgeCount, int]
  for recorded in decision.recorder.data.actions:
    var action = recorded
    if action.kind in {ActionWalkTo, ActionPing}:
      action.first = clamp(action.first, 0'i32, int32(ReplayGridTiles) - 1)
      action.second = clamp(action.second, 0'i32, int32(ReplayGridTiles) - 1)
    if not action.validAction():
      continue
    let index = game.world.pudgeIndex(action.pudgeId)
    if index < 0:
      reject("Local policy command has no Pudge Wars seat")
    let seat = uint32(game.world.pudges[index].lobbySeat)
    if match.seats[seat].owner != client.participant:
      reject("Local policy command belongs to another participant")
    if submitted[index] >= MaxBotCommandsPerTurn:
      continue
    if not client.submit(seat, action.encodeAction()):
      reject("Unable to queue a Pudge Wars bot command")
    inc submitted[index]

proc start*(match: NetworkMatch, event: RoomMessage) =
  ## Starts only the approved revision and confirms the initial hash.
  let client = match.client
  if match.started or event.kind != BeginMatch or
    event.match == 0 or event.match != client.match or
    event.revision != match.revision or client.snapshot.room != match.room or
    client.snapshot.revision != match.revision or
    event.hash != match.networkHash():
      reject("Pudge Wars setup changed or its initial state disagrees")
  match.started = true
  match.matchId = event.match
  client.send(RoomMessage(
    kind: ReportHash, match: match.matchId, tick: 0, hash: match.networkHash()
  ))
  match.flushSubmissions()

proc toIntent(action: ReplayAction, index: int): HumanIntent =
  ## Restores the local input form from a checked network action.
  for kind, command in ActionForIntent:
    if command == action.kind:
      return HumanIntent(
        slot: int32(index), kind: kind, a: action.first, b: action.second
      )
  reject("Pudge Wars action has no human intent")

proc applyPacket*(match: NetworkMatch, packet: RoomMessage) =
  ## Checks ownership before applying the relay's next immutable tick.
  let
    game = match.game
    client = match.client
  if not match.started or match.finished or packet.kind != TickPacket or
    packet.match != match.matchId or client.match != match.matchId or
    packet.tick != uint32(game.world.tick + 1) or
    packet.tick != client.applied + 1:
      reject("Unexpected Pudge Wars simulation tick")
  var
    actions: array[MaxPudgeCount, seq[ReplayAction]]
    chats: seq[MatchChatLine]
  for command in packet.commands:
    if command.participant == 0 or command.seat >= uint32(match.seats.len) or
      match.seats[command.seat].owner != command.participant:
        reject("Pudge Wars command participant does not own this seat")
    let index = match.seatPlayers[command.seat]
    if index < 0:
      reject("Pudge Wars command names an empty seat")
    let submission = decodeSubmission(command.payload)
    if submission.text.len > 0:
      if index notin game.humanSlots:
        reject("Pudge Wars chat requires a human seat")
      chats.add MatchChatLine(
        tick: int32(packet.tick), slot: int32(index),
        name: game.seatLabels[index], text: submission.text, team: -1
      )
    else:
      var action = submission.action
      action.tick = packet.tick
      action.pudgeId = game.world.pudges[index].id
      actions[index].add action
  game.tickWorld(proc() =
    ## Resolves each seat in the normal rotating hero turn order.
    let world = game.world
    for offset in 0 ..< world.pudges.len:
      let index = (world.heroTurnStart + offset) mod world.pudges.len
      if index in game.humanSlots:
        for action in actions[index]:
          game.queueIntent(action.toIntent(index))
        game.runHumanIntents(index)
      else:
        for action in actions[index]:
          game.recorder.record(action)
          world.applyReplayAction(action)
    world.heroTurnStart = (world.heroTurnStart + 1) mod world.pudges.len
  )
  if uint32(game.world.tick) != packet.tick:
    reject("Pudge Wars failed to execute the authoritative tick")
  if game.recordingError.len > 0:
    reject(game.recordingError)
  for line in chats:
    game.appendChat(line)
  match.finished = game.world.gameOver or game.world.tick >= game.maximumTicks
  client.appliedTick(packet.tick)
  if packet.tick mod uint32(NetworkTickRate) == 0:
    client.send(RoomMessage(
      kind: ReportHash, match: match.matchId, tick: packet.tick,
      hash: match.networkHash()
    ))
  if match.finished:
    client.send(RoomMessage(
      kind: FinishMatch, match: match.matchId, tick: packet.tick,
      hash: match.networkHash()
    ))
  else:
    match.flushSubmissions()

proc advanceNetwork*(match: NetworkMatch): bool =
  ## Advances at most one available tick without renderer-side smoothing.
  var packet: RoomMessage
  if match.started and not match.finished and match.client.takeTick(packet):
    match.applyPacket(packet)
    result = true
  else:
    match.flushSubmissions()

proc abort*(match: NetworkMatch, detail: string) =
  ## Stops advancement and reports a session failure to the shared relay.
  match.client.error = detail
  match.client.snapshot.phase = Desynced
  match.client.send(RoomMessage(
    kind: AbortMatch, match: match.client.match, detail: detail
  ))
