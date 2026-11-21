## Pudge Wars options extend the shared Polyworld command-line contract.

import
  std/strutils,
  polyworld/cli as commoncli

export commoncli except GameOptions, takeCommonFlag, validateGameOptions,
  setMaximumTicks, resolveGamePaths, MatchConfig

type GameOptions* = object
  common*: commoncli.GameOptions = commoncli.GameOptions()
  windowX*: int32 = -1
    ## Graphical window left edge in screen points; negative leaves placement to the system.
  windowY*: int32 = -1
    ## Graphical window top edge in screen points; negative leaves placement to the system.
  humanSlots*: seq[int32]
    ## Additional zero-based local human seats for Pudge practice tools.
  quickcast*: bool
    ## Abilities cast on key press at the cursor, skipping targeting.
  autocast*: bool
    ## Meat Hook autocast: right-click an enemy throws if the chain
    ## is ready; otherwise melee. Toggle from Controls or the Hook well.
  killGoal*: int32
    ## Score-goal override for games with one. Zero keeps the default.
  duel*: bool
    ## One-a-side duel roster for games that support it.
  teamSize*: int32
    ## Butchers a bank for N vs N (1..5). Zero means the game default.
  matchLogDir*: string
    ## Directory for structured per-match analysis logs. Empty off.
  botEvery*: int32
    ## Bot decision cadence in ticks. Zero or one means every tick.
  botAimNoise*: int32
    ## Bot aim scatter in tiles. Zero means perfect aim.
  runeSeconds*: int32
    ## Seconds between river rune spawns. -1 keeps the game default;
    ## 0 disables runes.
  keysPath*: string
    ## Optional key bindings file for the graphical client.
  practice*: bool
    ## Jev practice coach on the human seat: HUD cues plus a decision
    ## trace under `practiceDir`.
  practiceDir*: string
    ## Base directory for practice traces. Empty picks the user data dir.
  coachEndpoint*: string
    ## Decision-model endpoint for the coach and pilots: `jev`, `d1`,
    ## `local`, or a base URL. Empty picks Jev (TypeSafe).
  coachModel*: string
    ## Model name sent to the coach endpoint. Empty picks its default.
  pilotSlots*: seq[int32]
    ## Seats driven by the decision model through the human intent
    ## path, recorded as `pilot` traces.
  seatLabels*: seq[string]
    ## Per-roster nameplates. Coworld and the web viewer pass one
    ## `--label` per seat; later values fill seats in order.

template botGroups*(options: GameOptions): untyped =
  ## Exposes the shared botGroups option without duplicating its storage.
  options.common.botGroups

template replayPath*(options: GameOptions): untyped =
  ## Exposes the shared replayPath option without duplicating its storage.
  options.common.replayPath

template recordPath*(options: GameOptions): untyped =
  ## Exposes the shared recordPath option without duplicating its storage.
  options.common.recordPath

template capture*(options: GameOptions): untyped =
  ## Exposes the shared capture option without duplicating its storage.
  options.common.capture

template seed*(options: GameOptions): untyped =
  ## Exposes the shared seed option without duplicating its storage.
  options.common.seed

template seconds*(options: GameOptions): untyped =
  ## Exposes the shared seconds option without duplicating its storage.
  options.common.seconds

template maximumTicks*(options: GameOptions): untyped =
  ## Exposes the shared maximumTicks option without duplicating its storage.
  options.common.maximumTicks

template speed*(options: GameOptions): untyped =
  ## Exposes the shared speed option without duplicating its storage.
  options.common.speed

template verbose*(options: GameOptions): untyped =
  ## Exposes the shared verbose option without duplicating its storage.
  options.common.verbose

template viewMode*(options: GameOptions): untyped =
  ## Exposes the shared viewMode option without duplicating its storage.
  options.common.viewMode

template spawnIntervalTicks*(options: GameOptions): untyped =
  ## Exposes the shared spawnIntervalTicks option without duplicating its storage.
  options.common.spawnIntervalTicks

template pauseOnStart*(options: GameOptions): untyped =
  ## Exposes the shared pauseOnStart option without duplicating its storage.
  options.common.pauseOnStart

template windowWidth*(options: GameOptions): untyped =
  ## Exposes the shared windowWidth option without duplicating its storage.
  options.common.windowWidth

template windowHeight*(options: GameOptions): untyped =
  ## Exposes the shared windowHeight option without duplicating its storage.
  options.common.windowHeight

template vsync*(options: GameOptions): untyped =
  ## Exposes the shared vsync option without duplicating its storage.
  options.common.vsync

template playerSlot*(options: GameOptions): untyped =
  ## Exposes the shared playerSlot option without duplicating its storage.
  options.common.playerSlot

template playerName*(options: GameOptions): untyped =
  ## Exposes the shared playerName option without duplicating its storage.
  options.common.playerName

template soundMuted*(options: GameOptions): untyped =
  ## Exposes the shared soundMuted option without duplicating its storage.
  options.common.soundMuted

template soundOverride*(options: GameOptions): untyped =
  ## Exposes the shared soundOverride option without duplicating its storage.
  options.common.soundOverride

template headlessTickRate*(options: GameOptions): untyped =
  ## Exposes the shared headlessTickRate option without duplicating its storage.
  options.common.headlessTickRate

template waitForLlm*(options: GameOptions): untyped =
  ## Exposes the shared waitForLlm option without duplicating its storage.
  options.common.waitForLlm

template tickRate*(options: GameOptions): untyped =
  ## Exposes the shared tickRate option without duplicating its storage.
  options.common.tickRate

template specifiedFlags*(options: GameOptions): untyped =
  ## Exposes the shared specifiedFlags option without duplicating its storage.
  options.common.specifiedFlags

template serverUrl*(options: GameOptions): untyped =
  ## Exposes the shared serverUrl option without duplicating its storage.
  options.common.serverUrl

template roomCode*(options: GameOptions): untyped =
  ## Exposes the shared roomCode option without duplicating its storage.
  options.common.roomCode

proc parseWindowPos*(text, name: string): (int32, int32) =
  ## Parses one nonnegative screen position in X,Y form.
  let separator = text.find(',')
  if separator <= 0 or separator >= text.high:
    raise newException(ValueError, name & " must look like 400,80")
  result = (
    parseInt32(text[0 ..< separator], name),
    parseInt32(text[separator + 1 .. ^1], name)
  )
  if result[0] < 0 or result[1] < 0:
    raise newException(ValueError, name & " must not be negative")

proc takeCommonFlag*(
    options: var GameOptions,
    arguments: seq[string],
    index: var int,
    argument: string
): bool =
  ## Delegates common flags and retains Pudge's optional window placement.
  if options.common.takeCommonFlag(arguments, index, argument):
    return true
  if argument == "--windowPos":
    (options.windowX, options.windowY) = parseWindowPos(
      arguments.argumentValue(index, "--windowPos"), "--windowPos"
    )
    return true
  if argument.startsWith("--windowPos:") or
    argument.startsWith("--windowPos="):
      (options.windowX, options.windowY) =
        parseWindowPos(argument[12 .. ^1], "--windowPos")
      return true

proc validateGameOptions*(
    options: GameOptions,
    liveSlotCount: int,
    liveBotMessage: string,
    localLaunch = false
) =
  ## Uses shared validation while accounting for Pudge practice seats.
  when not defined(headless):
    options.common.rejectUnsupportedFlags(AllCommonFlags - {HeadlessTickRateFlag})
  options.common.validateGameOptions(0, liveBotMessage)
  if (options.serverUrl.len > 0 or options.roomCode.len > 0) and
    (localLaunch or options.botGroups.len > 0 or options.playerSlot > 0 or
      options.replayPath.len > 0 or options.humanSlots.len > 0 or
      options.pilotSlots.len > 0 or options.duel or options.practice):
      raise newException(CliError,
        "--server and --room use lobby seats; " &
        "do not combine them with local bots, players, or replays")
  if options.replayPath.len > 0:
    if options.humanSlots.len > 0 or options.pilotSlots.len > 0:
      raise newException(ValueError, "--replay cannot use human or pilot seats")
  elif liveSlotCount > 0:
    let needed = liveSlotCount - options.humanSlots.len - options.pilotSlots.len
    if options.botGroups.botCount != needed:
      raise newException(ValueError,
        liveBotMessage & "; expected " & $needed & " bots, configured " &
          $options.botGroups.botCount)

proc resolveGamePaths*(options: var GameOptions) =
  ## Resolves common input and output paths from the launch directory.
  options.common.resolveGamePaths()

proc addPracticePlayer*(options: var GameOptions, text: string) =
  ## Adds one one-based practice seat to the zero-based runtime roster.
  let slot = parsePositiveInt32(text, "--practice-player") - 1
  if slot in options.humanSlots or slot in options.pilotSlots:
    raise newException(ValueError, "That practice seat already has a controller")
  options.humanSlots.add slot

proc configurePlayerSlot*(options: var GameOptions) =
  ## Assigns the shared one-based player slot to the local runtime roster.
  if options.playerSlot == 0:
    return
  let slot = options.playerSlot - 1
  if slot in options.humanSlots or slot in options.pilotSlots:
    raise newException(ValueError, "--player overlaps another controller")
  options.humanSlots.insert(slot, 0)
