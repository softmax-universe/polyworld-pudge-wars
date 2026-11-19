import
  std/[strutils, unicode],
  polyworld/[hashes, roomclients, rooms],
  bots, content, maps, pacing, presets, replays, sim

export presets, roomclients, rooms

const
  NetworkProtocol* = 2'u32
  NetworkTickRate* = int(HumanTickRate)
  HumanSeatName* = "Human"
  MaxMatchChatBytes = 480
  MaxBotCommandsPerTurn = 64
  WarningTicks = 3 * 60 * int32(NetworkTickRate)
  ChatCommand = 0'u8
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
    setupDigest: uint64
    initial: RoomMessage
    seats: array[MaxPudgeCount, Seat]
    seatPlayers: array[MaxPudgeCount, int]
    botSeats: array[MaxPudgeCount, Seat]
    sources: array[MaxPudgeCount, string]
    sourceNames: array[MaxPudgeCount, string]
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
      seat.kind == HumanSeat:
        if result >= 0:
          reject("Each participant may control only one Pudge Wars human")
        result = i

proc claimHuman*(client: RoomClient, index: int) =
  ## Moves the local human without taking another participant's slot.
  if client.participant == 0 or index notin 0 ..< client.snapshot.seats.len or
    client.snapshot.seats[index].owner notin [0'u32, client.participant]:
      reject("That seat belongs to another participant")
  let old = client.snapshot.humanSeat(client.participant)
  if old >= 0 and old != index:
    client.send(RoomMessage(kind: ReleaseSeat, seat: uint32(old)))
  client.send(RoomMessage(
    kind: ClaimSeat, seat: uint32(index), seatKind: HumanSeat,
    name: HumanSeatName
  ))

proc seatAt(seats: openArray[Seat], index: int): Seat =
  ## Treats a generic live resize removing a stable slot as a vacancy.
  if index in 0 ..< seats.len:
    result = seats[index]

proc participantName(snapshot: RoomMessage, id: uint32): string =
  ## Looks up a name in the immutable match setup.
  for participant in snapshot.participants:
    if participant.id == id:
      return participant.name

proc ownsBot(client: RoomClient, seat: Seat, index: int): bool =
  ## Loads policy bytes only when the local client owns both views of a seat.
  client == nil or (seat.owner != 0 and seat.owner == client.participant and
    seat.kind == BotSeat and client.snapshot.seats.seatAt(index) == seat)

proc buildGame(
    config: MatchConfig,
    seats: openArray[Seat],
    localHuman: int,
    sources: openArray[string],
    client: RoomClient,
    snapshot = RoomMessage()
): Game =
  ## Packs occupied slots in bank order and loads policy bytes only locally.
  config.validateRoster(seats)
  if localHuman < -1 or localHuman >= seats.len or
    (localHuman >= 0 and seats[localHuman].owner == 0):
      reject("Invalid local Pudge Wars human seat")
  let networked = client != nil
  var
    roster: seq[ReplayPudge]
    labels: seq[string]
    humanSlots: seq[int]
  for lane in livePudgeSetup(false, config.teamSize):
    let
      i = int(lane.team) * MaxTeamSize + int(lane.slot)
      seat = seats[i]
    if seat.owner == 0:
      continue
    let human =
      if networked:
        seat.kind == HumanSeat
      else:
        i == localHuman
    var label = seat.name
    if networked:
      discard snapshot.humanSeat(seat.owner)
      let ownerName = snapshot.participantName(seat.owner)
      if ownerName.len == 0 or seat.name.len == 0:
        reject("Occupied Pudge Wars seat is missing its owner or label")
      if human:
        label = ownerName
    if human:
      humanSlots.add roster.len
    elif client.ownsBot(seat, i) and
      (i >= sources.len or sources[i].len == 0):
        reject("Choose a local policy for Pudge Wars seat " & $(i + 1))
    var entry = lane
    entry.lobbySeat = uint8(i)
    roster.add entry
    labels.add label
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
  result.heroVms.setLen(result.world.pudges.len)
  try:
    for index, pudge in result.world.pudges:
      let i = int(pudge.lobbySeat)
      if index notin humanSlots and client.ownsBot(seats[i], i):
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
    snapshot = client.setupSnapshot()
    config = parseConfig(snapshot.payload)
    human = snapshot.humanSeat(client.participant)
  if client.identity != identity() or snapshot.room.len == 0 or
    snapshot.tickRate != uint32(NetworkTickRate):
      reject("Pudge Wars room identity or tick rate differs from this client")
  let game = buildGame(config, snapshot.seats, human, sources, client, snapshot)
  var setupHash = HashySeed
  setupHash.addHashy(config)
  setupHash.addHashy(contentHash())
  setupHash.addHashy(snapshot.seats)
  setupHash.addHashy(game.seatLabels)
  result = NetworkMatch(
    client: client, game: game, room: snapshot.room, initial: snapshot,
    revision: snapshot.revision, humanIndex: game.world.worldIndexOfSeat(human),
    setupHash: setupHash, setupDigest: snapshot.setupHash()
  )
  for i in 0 ..< MaxPudgeCount:
    result.seatPlayers[i] = -1
    result.seats[i] = snapshot.seats[i]
    let live = client.snapshot.seats.seatAt(i)
    if i < sources.len and client.ownsBot(live, i):
      result.sources[i] = sources[i]
      result.sourceNames[i] = live.name
  for i, pudge in game.world.pudges:
    result.seatPlayers[pudge.lobbySeat] = i
    if game.heroVms[i] != nil:
      result.botSeats[i] = result.seats[pudge.lobbySeat]

proc startRequest*(match: NetworkMatch): RoomMessage =
  ## Starts the exact prepared lobby through the game-independent envelope.
  let
    client = match.client
    snapshot = client.snapshot
  if client.began or snapshot.phase != Lobby or snapshot.room != match.room or
    snapshot.participant != client.participant or
    snapshot.revision != match.revision or
    snapshot.setupHash() != match.setupDigest:
      reject("Pudge Wars room changed before the owner could start it")
  RoomMessage(kind: StartMatch, revision: match.revision, hash: match.setupDigest)

proc humanPudgeIndex*(match: NetworkMatch): int =
  ## Returns the local player's packed roster index, or -1 for a spectator.
  if match.humanIndex >= 0:
    let
      index = int(match.game.world.pudges[match.humanIndex].lobbySeat)
      live = match.client.snapshot.seats.seatAt(index)
    if live.owner == match.client.participant and live.kind == HumanSeat:
      return match.humanIndex
  -1

proc networkHash*(match: NetworkMatch): uint64 =
  ## Includes static room settings as well as the evolving replay state.
  var routingHash = match.setupHash
  for pudge in match.game.world.pudges:
    routingHash.addHashy(match.seats[pudge.lobbySeat])
  (uint64(routingHash) shl 32) xor match.game.stateHash()

proc reopenedLobby*(match: NetworkMatch): bool =
  ## Lets the renderer yield after the host reopens this room for a rematch.
  match != nil and match.started and not match.client.began and
    (match.client.snapshot.room.len == 0 or
      (match.client.snapshot.room == match.room and
        match.client.snapshot.phase == Lobby))

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
  if kind == uint32(ChatCommand):
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
    not match.client.catchingUp and match.client.snapshot.phase == Playing

proc canDrive(match: NetworkMatch, seat: uint32, kind: SeatKind): bool =
  ## Requires both the applied tick and the current room to route this input.
  let controller = match.seats[seat]
  controller.owner != 0 and controller.owner == match.client.participant and
    controller.kind == kind and
    match.client.snapshot.seats.seatAt(int(seat)) == controller

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
    let seat = uint32(match.game.world.pudges[match.humanIndex].lobbySeat)
    if match.canDrive(seat, HumanSeat):
      result = match.client.submit(seat, action.encodeAction())

proc queueChat*(match: NetworkMatch, text: string): bool =
  ## Submits an ordinary room-wide chat line from the local human seat.
  let message = strutils.strip(text)
  if not match.canSubmit() or match.humanIndex < 0 or not message.validChat():
    return false
  var bytes: string
  bytes.put32(uint32(ChatCommand))
  bytes.putString(message)
  let seat = uint32(match.game.world.pudges[match.humanIndex].lobbySeat)
  match.canDrive(seat, HumanSeat) and match.client.submit(seat, bytes)

proc closeBot(match: NetworkMatch, index: int) =
  ## Releases a private VM after its authoritative controller changes.
  let vm = match.game.heroVms[index]
  if vm != nil and vm.closeServices != nil:
    vm.closeServices()
  match.game.heroVms[index] = nil
  if match.decision != nil:
    match.decision.heroVms[index] = nil
  match.botSeats[index] = Seat()

proc loadAssignedBot(match: NetworkMatch, index: int, seat: uint32) =
  ## Restores a matching local policy or an exactly named bundled policy.
  let controller = match.seats[seat]
  var source: string
  if match.sourceNames[seat] == controller.name:
    source = match.sources[seat]
  if source.len == 0:
    for (name, bundled) in BotPolicies:
      if name == controller.name:
        source = bundled
        break
  if source.len == 0:
    reject("No local BASIC policy for the transferred seat " & controller.name)
  try:
    match.game.loadBotSource(index, source, nil, nil)
  except CatchableError as error:
    echo "pudge ", match.game.world.pudges[index].id, " BASIC error: ", error.msg
    reject("Cannot load BASIC policy for " & controller.name)
  match.botSeats[index] = controller

proc flushSubmissions*(match: NetworkMatch) =
  ## Runs each locally owned bot once at the confirmed live edge.
  let
    game = match.game
    client = match.client
    tick = game.world.tick + 1
  var canceled: RoomMessage
  while client.takeRejected(canceled):
    discard
  if not match.canSubmit() or client.snapshot.flag or match.decisionTick == tick:
      return
  match.decisionTick = tick
  var
    ready: bool
    readySeats: array[MaxPudgeCount, bool]
  for i, pudge in game.world.pudges:
    let seat = uint32(pudge.lobbySeat)
    if not match.canDrive(seat, BotSeat):
      continue
    if game.heroVms[i] == nil:
      match.loadAssignedBot(i, seat)
    if not game.heroVms[i].failed and pudge.state != Dying and
      (tick + int32(i)) mod game.botEvery == 0 and
      not client.hasPendingCommand(seat):
        readySeats[i] = true
        ready = true
  if not ready:
    return
  if match.decision == nil:
    match.decision = Game(
      world: game.world.clone(), map: game.map, networked: true,
      heroVms: newSeq[HeroVm](game.heroVms.len),
      botEvery: game.botEvery, botAimNoise: game.botAimNoise,
      botSpeech: game.botSpeech,
      recorder: initReplayRecorder(game.recorder.data.header.setup)
    )
  else:
    match.decision.world.restore(game.world)
  let decision = match.decision
  decision.world.tick = tick
  decision.recorder.data.actions.setLen(0)
  decision.humanSlots = game.humanSlots
  for i, vm in game.heroVms:
    decision.heroVms[i] = if readySeats[i]: vm else: nil
    # The ping planner uses the human list to skip roles without a bot.
    if match.seats[game.world.pudges[i].lobbySeat].owner == 0:
      decision.humanSlots.add i
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
    if not match.canDrive(seat, BotSeat):
      continue
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
    event.revision != match.revision or event.room != match.room or
    event.hash != match.setupDigest or event.setupHash() != event.hash:
      reject("Pudge Wars setup changed or its initial state disagrees")
  match.started = true
  match.matchId = event.match
  client.send(RoomMessage(
    kind: ReportHash, match: match.matchId, tick: 0, hash: match.networkHash()
  ))
  match.flushSubmissions()

proc applyPacket*(match: NetworkMatch, packet: RoomMessage) =
  ## Uses the relay's stamped commands and the tick's sealed routing roster.
  let
    game = match.game
    client = match.client
  if not match.started or match.finished or packet.kind != TickPacket or
    packet.match != match.matchId or client.match != match.matchId or
    packet.tick != uint32(game.world.tick + 1) or
    packet.tick != client.applied + 1 or packet.seats.len == 0:
      reject("Unexpected Pudge Wars simulation tick")
  var
    actions: seq[ReplayAction]
    controllers: array[MaxPudgeCount, Seat]
    humanOwners: seq[uint32]
    humanSlots: seq[int]
    localHuman = -1
    controlledTick: bool
  for index, pudge in game.world.pudges:
    let
      seat = int(pudge.lobbySeat)
      controller = packet.seats.seatAt(seat)
    controllers[seat] = controller
    if client.participant != 0 and
      client.participant in [controller.owner, match.seats[seat].owner]:
        controlledTick = true
    if controller.owner == 0 or controller.kind != HumanSeat:
      continue
    if controller.owner in humanOwners:
      reject("Each participant may control only one Pudge Wars human")
    humanOwners.add controller.owner
    humanSlots.add index
    if controller.owner == client.participant:
      localHuman = index
  for command in packet.commands:
    if command.participant == 0 or command.sequence == 0:
      reject("Pudge Wars command lacks authenticated routing")
    # The relay stamps ownership at acceptance, before possible handoffs.
    if command.seat >= uint32(MaxPudgeCount):
      continue
    let index = match.seatPlayers[command.seat]
    if index < 0:
      # Slots added after initialization enter gameplay in the next match.
      continue
    if command.participant == client.participant:
      controlledTick = true
    let submission = decodeSubmission(command.payload)
    if submission.text.len > 0:
      if command.seatKind != HumanSeat:
        reject("Pudge Wars chat requires a human seat")
      let playerName = match.initial.participantName(command.participant)
      actions.add ReplayAction(
        source: HumanCommand, kind: ActionChat, tick: packet.tick,
        pudgeId: game.world.pudges[index].id, first: int32(index), second: -1,
        name: (if playerName.len > 0: playerName
          else: "Player " & $command.participant), text: submission.text
      )
    else:
      var action = submission.action
      action.tick = packet.tick
      action.pudgeId = game.world.pudges[index].id
      action.source =
        if command.seatKind == HumanSeat: HumanCommand else: BotCommand
      actions.add action
  # Preserve admission order on tape; dispatch still uses hero-turn phases.
  for index, pudge in game.world.pudges:
    let human = index in humanSlots
    if human != (index in game.humanSlots):
      game.recorder.recordTakeOver(packet.tick, pudge.id,
        if human: ControllerHuman else: ControllerBot)
  for action in actions:
    game.recorder.record(action)
  game.tickWorld(proc() =
    ## Uses the same phase executor as ordered network replay playback.
    game.applyNetworkActions(actions, humanSlots)
  )
  if uint32(game.world.tick) != packet.tick:
    reject("Pudge Wars failed to execute the authoritative tick")
  if game.recordingError.len > 0:
    reject(game.recordingError)
  for action in actions:
    if action.kind == ActionChat:
      game.appendChat(MatchChatLine(
        tick: int32(action.tick), slot: action.first, team: action.second,
        name: action.name, text: action.text
      ))
  let warningTick = game.maximumTicks - WarningTicks
  if warningTick > 0 and game.world.tick == warningTick and
    not game.world.gameOver:
      game.recordChat(MatchChatLine(
        tick: warningTick, slot: -1, name: "Match", text: "3 minutes remain",
        team: -1
      ))
  for index, pudge in game.world.pudges:
    if match.botSeats[index].owner != 0 and
      match.botSeats[index] != controllers[pudge.lobbySeat]:
        match.closeBot(index)
  match.seats = controllers
  match.humanIndex = localHuman
  game.humanSlots = humanSlots
  match.finished = game.world.gameOver or game.world.tick >= game.maximumTicks
  client.appliedTick(packet.tick)
  if packet.tick mod uint32(NetworkTickRate) == 0:
    client.send(RoomMessage(
      kind: ReportHash, match: match.matchId, tick: packet.tick,
      hash: match.networkHash()
    ))
  if match.finished and controlledTick:
    client.send(RoomMessage(
      kind: FinishMatch, match: match.matchId, tick: packet.tick,
      hash: match.networkHash()
    ))
  elif not match.finished:
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
