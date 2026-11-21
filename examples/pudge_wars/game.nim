## Pudge Wars match setup, command line, and the headless runner.

import
  std/[os, strformat, strutils, tables],
  polyworld/[profiles, tapes],
  pudgewars/cli,
  content,
  maps,
  sim,
  bots,
  practice,
  hybrid,
  replays,
  multiplayer

when defined(headless):
  import std/[times, monotimes]
  import branch

var
  serverAddress*, roomCode*: string
  directPlay*: bool

proc usage() =
  echo "Pudge Wars"
  echo "  --bot:PATH              Fill butcher slots with that script."
  echo "  --bot:PATH:N            Fill N slots with that file."
  echo "  --bot PATH[:N]          The equivalent two-argument form."
  echo "  --human[:SLOT]          A human drives one slot (0-based;"
  echo "                          default the first free slot)."
  echo "                          Repeatable. Bots fill the rest."
  echo "  --team-size N           N vs N, N=1..5 (default 3). Spawns"
  echo "                          2N butchers. --duel is still the"
  echo "                          ladder 1v1 (slot 1 of the 3-lane pads)."
  echo "  --duel                  1v1 mode: one butcher a side on the"
  echo "                          middle lane. Bots default to"
  echo "                          players/challenger.bas; first to " &
    $DuelKillGoal & "."
  echo "  --duellog DIR           Write per-match analysis logs (events"
  echo "                          .jsonl, summary.json, history.jsonl)"
  echo "                          under DIR. Defaults to duels/ in duel"
  echo "                          mode; also works for NvN and replays."
  echo "  --replay PATH           Play an action replay instead of bots."
  echo "  --branch PATH           Headless: score decision windows of a"
  echo "                          recorded match by counterfactual rollout"
  echo "                          (see --branch-ticks, --branch-slot)."
  echo "  --branch-ticks T,T,...  Window ticks to branch at."
  echo "  --branch-slot N         Traced seat (0-based)."
  echo "  --branch-options A,B    Option ids to score (default every"
  echo "                          eligible one plus none)."
  echo "  --horizon TICKS         Rollout length (default " &
    $(5 * TickRate) & ")."
  echo "  --branch-seeds N        Rollouts per option (default 1)."
  echo "  --branch-out PATH       JSONL output (default stdout)."
  echo "  --branch-teachers A,B   Scripts asked what they would do at"
  echo "                          each window (one teacher row each)."
  echo "  --branch-bot PATH       Script for the other seats after the"
  echo "                          branch (default players/base.bas)."
  echo "  --record PATH           Record match actions to a replay."
  echo "  --seconds NUMBER        Duration in seconds (default 1200)."
  echo "  --minutes NUMBER        Duration in minutes (default 20)."
  echo "  --ticks NUMBER          Duration in ticks (default 38400)."
  echo "  --seed NUMBER           Live game map seed."
  echo "  --killGoal NUMBER       First team to NUMBER kills wins" &
    " (default " & $KillGoal & ")."
  echo "  --botEvery NUMBER       Bots decide every NUMBER ticks" &
    " (default 1)."
  echo "  --botAimNoise NUMBER    Bot hook aim scatter in tiles" &
    " (default 0)."
  echo "  --runes NUMBER          Seconds between river rune drops" &
    " (default " & $(RunePeriodTicks div TickRate) &
    "; public north/south + kind cycle; 0 disables)."
  echo "  --difficulty NAME       Bot preset: easy, fair, or pro."
  echo "  --practice              Jev practice coach on the human seat:"
  echo "                          live cues on the HUD (P hides them) and a"
  echo "                          decision trace per match."
  echo "  --hybrid:SLOT           BASIC plays continuously; D1 advises target,"
  echo "                          lane and aggression (--coach local|none)."
  echo "  --hybrid-delay-ticks N  Minimum observation-to-application delay."
  echo "  --hybrid-plan PATH      Replay a tactical intervention JSON array"
  echo "                          without inference (one hybrid seat only)."
  echo "  --tactical-shadow:SLOT Record tactical windows without controlling"
  echo "                          this human or BASIC seat (for coaching)."
  echo "  --practice-dir DIR      Where practice traces go (default the"
  echo "                          user data dir)."
  echo "  --coach NAME|URL        Decision model for the coach and pilots:"
  echo "                          jev (TypeSafe, default), d1 (Liquid),"
  echo "                          local (sidecar on 127.0.0.1:8765), or a"
  echo "                          base URL. Keys: typesafe.key, liquid.key."
  echo "  --coach-model NAME      Model name for that endpoint."
  echo "  --shadow[:SLOT]         Record a script seat as a teacher trace"
  echo "                          (bot-SLOT/ beside the match; bare = every"
  echo "                          script seat)."
  echo "  --pilot-noise P         Pilots execute a random eligible option"
  echo "                          instead of the cue with chance P (0..1)."
  echo "  --asks periodic         Open decision windows on the heartbeat only"
  echo "                          (default: also on contact, hooks, deaths)."
  echo "  --thresholds PATH       Fitted confidence thresholds for cues and"
  echo "                          pilots (default <data dir>/thresholds.json;"
  echo "                          --thresholds:off keeps the constants)."
  echo "  --pilot[:SLOT]          The decision model drives one slot"
  echo "                          through the human intent path and"
  echo "                          records a pilot trace. Repeatable."
  echo "  --quickcast             Hook casts on key press at the cursor."
  echo "  --autocast              Meat Hook autocast: RMB an enemy throws."
  echo "  --keys PATH             Key bindings file (action = KeyName)."
  echo "  --mute                  Start with the sound off (M toggles)."
  echo "  --sound                 Start with the sound on."
  echo "  --play=false            Start the graphical transport paused."
  echo "  --speed NUMBER          Graphical start speed: 1, 2, 4, or 16."
  echo "  --windowSize WxH        Graphical window, such as 1024x576."
  echo "  --screenshot PATH       Save a native screenshot and exit."
  echo "  --frames N              Capture after N rendered frames (default 30)."
  echo "  --windowPos X,Y         Place the window at screen point X,Y (top-left)."
  echo "  --vsync:off             Unlock the frame rate (default on)."
  echo "  --server URL            Shared multiplayer relay address."
  echo "  --room CODE             Open multiplayer and join a room."
  echo "  --name TEXT             Saved multiplayer display name."
  echo "  --label TEXT            Per-seat nameplate for local replay tools."
  echo "Compile with -d:headless for command-line simulation."
  echo "Compile with -d:emscripten for the web backend."

proc takePwDurationFlag(
    options: var GameOptions,
    arguments: seq[string],
    index: var int,
    argument: string
): bool =
  ## `--seconds` / `--minutes` / `--ticks` at this game's 32 Hz tick rate.
  var
    name = ""
    text = ""
  if argument.startsWith("--seconds="):
    name = "--seconds"
    text = argument[10 .. ^1]
  elif argument.startsWith("--minutes="):
    name = "--minutes"
    text = argument[11 .. ^1]
  elif argument.startsWith("--ticks="):
    name = "--ticks"
    text = argument[8 .. ^1]
  else:
    case argument
    of "--seconds", "--minutes", "--ticks":
      name = argument
      text = arguments.argumentValue(index, argument)
    else:
      return false
  let count = parsePositiveInt32(text, name)
  var ticks = int64(count)
  case name
  of "--seconds":
    ticks = int64(count) * int64(TickRate)
  of "--minutes":
    ticks = int64(count) * 60'i64 * int64(TickRate)
  of "--ticks":
    discard
  else:
    return false
  if ticks > int32.high:
    fail(name & " is too large")
  options.maximumTicks = int32(ticks)
  options.seconds = options.maximumTicks div TickRate
  true

proc addHumanSlot(options: var GameOptions, text: string) =
  ## Adds one human seat: an explicit slot index or the first free one.
  var slot = -1'i32
  if text.len > 0:
    slot = parseInt32(text, "--human")
    if slot < 0 or slot >= MaxPudgeCount:
      fail("--human slot must be between 0 and " & $(MaxPudgeCount - 1))
  else:
    for candidate in 0'i32 ..< int32(MaxPudgeCount):
      if candidate notin options.humanSlots:
        slot = candidate
        break
    if slot < 0:
      fail("every slot already has a human")
  if slot in options.humanSlots:
    fail("slot " & $slot & " already has a human")
  options.humanSlots.add slot

proc addPilotSlot(options: var GameOptions, text: string) =
  ## Adds one model-driven seat: an explicit slot or the first free one.
  var slot = -1'i32
  if text.len > 0:
    slot = parseInt32(text, "--pilot")
    if slot < 0 or slot >= MaxPudgeCount:
      fail("--pilot slot must be between 0 and " & $(MaxPudgeCount - 1))
  else:
    for candidate in 0'i32 ..< int32(MaxPudgeCount):
      if candidate notin options.humanSlots and
          candidate notin options.pilotSlots:
        slot = candidate
        break
    if slot < 0:
      fail("every slot already has a human or pilot")
  if slot in options.humanSlots or slot in options.pilotSlots:
    fail("slot " & $slot & " already has a human or pilot")
  options.pilotSlots.add slot

proc applyDifficulty(options: var GameOptions, name: string) =
  ## Bot handicap presets; explicit knob flags given later still win.
  case name.strip().toLowerAscii()
  of "easy":
    options.botEvery = 16
    options.botAimNoise = 2
  of "fair":
    options.botEvery = 8
    options.botAimNoise = 1
  of "pro":
    options.botEvery = 1
    options.botAimNoise = 0
  else:
    fail("--difficulty must be easy, fair, or pro")

proc findStockBot(): string =
  ## Default autopilot policy for empty seats.
  for candidate in [
    "examples/pudge_wars/players/base.bas",
    "players/base.bas"
  ]:
    if fileExists(candidate):
      return candidate
  result = getTempDir() / "pudge-base.bas"
  writeFile(result, StockBotSource)

proc findChallengerScript(): string =
  ## The evolving duel policy, looked up from the repo root or the
  ## example directory.
  const ChallengerSource = staticRead("players/challenger.bas")
  for candidate in [
    "examples/pudge_wars/players/challenger.bas",
    "players/challenger.bas"
  ]:
    if fileExists(candidate):
      return candidate
  result = getTempDir() / "pudge-challenger.bas"
  writeFile(result, ChallengerSource)

when defined(headless):
  var branchOptions*: BranchOptions
    ## `--branch`: score recorded decision windows instead of playing.

var
  thresholdsPath* = ""
    ## `--thresholds PATH`: fitted confidence thresholds for the coach
    ## and pilots. Empty reads `<data dir>/thresholds.json` when present.
  thresholdsOff* = false
    ## `--thresholds:off`: keep the built-in constants.

var
  pilotNoise* = 0.0
  hybridSlots*: seq[int]
  tacticalShadowSlots*: seq[int]
  hybridDelay* = 0'i32
  hybridPlan* = ""
  shadowSlots*: seq[int32]
    ## `--shadow:SLOT`: script seats recorded as teacher traces.
  shadowAll* = false
    ## `--shadow`: every script seat.
    ## `--pilot-noise P`: chance per window that a pilot executes a random
    ## eligible option instead of its cue (mistake coverage for traces).

proc takeThresholdFlag(arguments: seq[string], index: var int,
    argument: string): bool =
  if argument.startsWith("--tactical-shadow:"):
    let slot = int(parseInt32(argument[18 .. ^1], "--tactical-shadow"))
    if slot notin tacticalShadowSlots: tacticalShadowSlots.add slot
  elif argument.startsWith("--hybrid:"):
    let slot = int(parseInt32(argument[9 .. ^1], "--hybrid"))
    if slot notin hybridSlots: hybridSlots.add slot
  elif argument == "--hybrid-delay-ticks":
    hybridDelay = parseInt32(arguments.argumentValue(index, argument), argument)
    if hybridDelay < 0: fail("--hybrid-delay-ticks must be nonnegative")
  elif argument == "--hybrid-plan":
    hybridPlan = arguments.argumentValue(index, argument)
  elif argument == "--shadow":
    shadowAll = true
  elif argument.startsWith("--shadow:"):
    shadowSlots.add parseInt32(argument[9 .. ^1], "--shadow")
  elif argument == "--pilot-noise":
    pilotNoise = parseFloat(arguments.argumentValue(index, "--pilot-noise"))
  elif argument.startsWith("--pilot-noise="):
    pilotNoise = parseFloat(argument[14 .. ^1])
  elif argument == "--asks":
    askEvents = arguments.argumentValue(index, "--asks") != "periodic"
  elif argument.startsWith("--asks="):
    askEvents = argument[7 .. ^1] != "periodic"
  elif argument == "--thresholds":
    thresholdsPath = arguments.argumentValue(index, "--thresholds")
  elif argument.startsWith("--thresholds="):
    thresholdsPath = argument[13 .. ^1]
  elif argument == "--thresholds:off":
    thresholdsOff = true
  else:
    return false
  true

proc takeBranchFlag(options: var GameOptions, arguments: seq[string],
    index: var int, argument: string): bool =
  ## Handles one answer-key flag. The tape also becomes --replay so the
  ## ordinary replay game is built for the rollouts to clone.
  when defined(headless):
    template value(name: string): string =
      arguments.argumentValue(index, name)
    case argument
    of "--branch":
      branchOptions.path = value("--branch")
      options.replayPath = branchOptions.path
    of "--branch-ticks":
      branchOptions.ticks = parseTicks(value("--branch-ticks"))
    of "--branch-slot":
      branchOptions.slot = int(parseInt32(value("--branch-slot"), "--branch-slot"))
    of "--branch-options":
      for part in value("--branch-options").split(','):
        if part.strip().len > 0:
          branchOptions.options.add part.strip()
    of "--horizon":
      branchOptions.horizon = parsePositiveInt32(value("--horizon"), "--horizon")
    of "--branch-seeds":
      branchOptions.seeds = int(parsePositiveInt32(value("--branch-seeds"), "--branch-seeds"))
    of "--branch-out":
      branchOptions.outPath = value("--branch-out")
    of "--branch-teachers":
      for part in value("--branch-teachers").split(','):
        if part.strip().len > 0:
          branchOptions.teachers.add part.strip()
    of "--branch-bot":
      branchOptions.botPath = value("--branch-bot")
    else:
      return false
    true
  else:
    false

proc parseGameOptions(): GameOptions =
  # killGoal and duration start unset (zero) so duel mode can pick its
  # own defaults after the flags are read.
  result = GameOptions(
    seed: 2026,
    speed: 1,
    windowWidth: 0,
    windowHeight: 0,
    botEvery: 1,
    runeSeconds: -1,
    mute: false
  )
  let arguments = commandLineParams()
  var index = 0
  while index < arguments.len:
    let argument = arguments[index]
    if argument in ["--human", "--bot", "--duel", "--practice", "--pilot",
      "--record"] or
      argument.startsWith("--human:") or argument.startsWith("--bot:") or
      argument.startsWith("--bot=") or argument.startsWith("--pilot:") or
      argument.startsWith("--hybrid:") or argument.startsWith("--record=") or
      argument.startsWith("--record:"):
        directPlay = true
    if result.takePwDurationFlag(arguments, index, argument):
      discard
    elif result.takeBranchFlag(arguments, index, argument):
      discard
    elif takeThresholdFlag(arguments, index, argument):
      discard
    elif result.takeCommonFlag(arguments, index, argument):
      discard
    elif argument == "--human":
      result.addHumanSlot("")
    elif argument.startsWith("--human:"):
      result.addHumanSlot(argument[8 .. ^1])
    elif argument == "--duel":
      result.duel = true
    elif argument == "--team-size":
      result.teamSize = parsePositiveInt32(
        arguments.argumentValue(index, "--team-size"), "--team-size"
      )
    elif argument.startsWith("--team-size="):
      result.teamSize = parsePositiveInt32(argument[12 .. ^1], "--team-size")
    elif argument == "--duellog":
      result.matchLogDir = arguments.argumentValue(index, "--duellog")
    elif argument.startsWith("--duellog="):
      result.matchLogDir = argument[10 .. ^1]
    elif argument == "--practice":
      result.practice = true
    elif argument == "--practice:off" or argument == "--no-practice":
      result.practice = false
    elif argument == "--practice-dir":
      result.practiceDir = arguments.argumentValue(index, "--practice-dir")
    elif argument.startsWith("--practice-dir="):
      result.practiceDir = argument[15 .. ^1]
    elif argument == "--coach":
      result.coachEndpoint = arguments.argumentValue(index, "--coach")
    elif argument.startsWith("--coach="):
      result.coachEndpoint = argument[8 .. ^1]
    elif argument == "--coach-model":
      result.coachModel = arguments.argumentValue(index, "--coach-model")
    elif argument.startsWith("--coach-model="):
      result.coachModel = argument[14 .. ^1]
    elif argument == "--pilot":
      result.addPilotSlot("")
    elif argument.startsWith("--pilot:"):
      result.addPilotSlot(argument[8 .. ^1])
    elif argument == "--quickcast":
      result.quickcast = true
    elif argument == "--autocast":
      result.autocast = true
    elif argument == "--mute":
      result.mute = true
    elif argument in ["--sound", "--unmute"]:
      result.mute = false
    elif argument == "--keys":
      result.keysPath = arguments.argumentValue(index, "--keys")
    elif argument.startsWith("--keys="):
      result.keysPath = argument[7 .. ^1]
    elif argument == "--killGoal":
      result.killGoal = parsePositiveInt32(
        arguments.argumentValue(index, "--killGoal"), "--killGoal"
      )
    elif argument.startsWith("--killGoal="):
      result.killGoal = parsePositiveInt32(argument[11 .. ^1], "--killGoal")
    elif argument == "--botEvery":
      result.botEvery = parsePositiveInt32(
        arguments.argumentValue(index, "--botEvery"), "--botEvery"
      )
    elif argument.startsWith("--botEvery="):
      result.botEvery = parsePositiveInt32(argument[11 .. ^1], "--botEvery")
    elif argument == "--botAimNoise":
      result.botAimNoise = parseInt32(
        arguments.argumentValue(index, "--botAimNoise"), "--botAimNoise"
      )
    elif argument.startsWith("--botAimNoise="):
      result.botAimNoise = parseInt32(argument[14 .. ^1], "--botAimNoise")
    elif argument == "--runes":
      result.runeSeconds = parseInt32(
        arguments.argumentValue(index, "--runes"), "--runes"
      )
    elif argument.startsWith("--runes="):
      result.runeSeconds = parseInt32(argument[8 .. ^1], "--runes")
    elif argument == "--difficulty":
      result.applyDifficulty(
        arguments.argumentValue(index, "--difficulty")
      )
    elif argument.startsWith("--difficulty="):
      result.applyDifficulty(argument[13 .. ^1])
    elif argument == "--server":
      serverAddress = arguments.argumentValue(index, "--server")
    elif argument.startsWith("--server="):
      serverAddress = argument[9 .. ^1]
    elif argument == "--room":
      roomCode = arguments.argumentValue(index, "--room")
    elif argument.startsWith("--room="):
      roomCode = argument[7 .. ^1]
    elif argument == "--name":
      result.playerName = arguments.argumentValue(index, "--name")
    elif argument.startsWith("--name="):
      result.playerName = argument[7 .. ^1]
    elif argument == "--label":
      result.seatLabels.add arguments.argumentValue(index, "--label")
    elif argument.startsWith("--label="):
      result.seatLabels.add argument[8 .. ^1]
    else:
      case argument
      of "--help", "-h":
        usage()
        quit(0)
      else:
        fail("unknown argument: " & argument)
    inc index
  # Unset goal and duration take the mode's defaults: duels are
  # shorter so the play-analyze-improve loop turns around quickly.
  if result.teamSize == 0:
    result.teamSize = int32(TeamSize)
  elif result.teamSize < 1 or result.teamSize > MaxTeamSize:
    fail("--team-size must be between 1 and " & $MaxTeamSize)
  if result.duel and result.teamSize != int32(TeamSize):
    fail("--duel cannot combine with --team-size")
  if result.killGoal <= 0:
    result.killGoal = if result.duel: DuelKillGoal else: KillGoal
  if result.maximumTicks <= 0:
    let minutes = if result.duel: DuelMinutes else: cli.DefaultMinutes
    result.maximumTicks = minutes * 60 * TickRate
    result.seconds = result.maximumTicks div TickRate
  if result.duel:
    for slot in result.humanSlots:
      if slot >= DuelPudgeCount:
        fail("--duel seats are 0 (west) and 1 (east)")
  if result.botAimNoise < 0:
    fail("--botAimNoise must be zero or positive")
  if result.runeSeconds >= 0 and
      int64(result.runeSeconds) * int64(TickRate) > int64(int32.high):
    fail("--runes is too large")
  let seats =
    if result.duel: DuelPudgeCount
    else: matchPudgeCount(int(result.teamSize))
  for slot in result.humanSlots:
    if slot >= seats:
      fail("--human slot " & $slot & " is outside this roster of " & $seats)
  for slot in result.pilotSlots:
    if slot >= seats:
      fail("--pilot slot " & $slot & " is outside this roster of " & $seats)
  for slot in hybridSlots:
    if slot < 0 or slot >= seats: fail("--hybrid slot is outside the roster")
    if int32(slot) in result.humanSlots or int32(slot) in result.pilotSlots:
      fail("--hybrid needs a BASIC seat, not a human or pilot seat")
  for slot in tacticalShadowSlots:
    if slot < 0 or slot >= seats: fail("--tactical-shadow slot is outside the roster")
    if slot in hybridSlots or int32(slot) in result.pilotSlots:
      fail("tactical shadow seats cannot overlap hybrid or pilot seats")
  if tacticalShadowSlots.len > 0 and result.replayPath.len > 0:
    fail("--tactical-shadow is currently supported for local live matches only")
  if hybridSlots.len > 0:
    if result.pilotSlots.len > 0:
      fail("--hybrid cannot share a match with blocking --pilot seats")
    if result.replayPath.len > 0:
      fail("--hybrid is currently supported for local live matches only")
    if result.coachEndpoint.len == 0: result.coachEndpoint = "local"
  if hybridPlan.len > 0 and hybridSlots.len != 1:
    fail("--hybrid-plan requires exactly one --hybrid seat")
  result.validateGameOptions(0, "")
  if result.recordPath.len > 0 or result.matchLogDir.len > 0:
    directPlay = true
  if result.replayPath.len == 0 and
    (defined(headless) or defined(takeScreenshot) or directPlay):
    if result.duel and result.botGroups.len == 0 and
        result.humanSlots.len < seats:
      # A bare duel pits the seats without humans against the
      # evolving challenger policy.
      result.botGroups.addBotSpec(
        findChallengerScript() & ":" &
          $(seats - result.humanSlots.len - result.pilotSlots.len)
      )
    elif result.botGroups.len == 0:
      # Local --human and spectate: stock autopilot on every seat.
      # Human seats still take input;
      # the VM is fallback if they release (T).
      result.botGroups.addBotSpec(findStockBot() & ":" & $seats)
    let
      bots = result.botGroups.botCount
      humans = result.humanSlots.len
    if bots != seats and bots + humans != seats:
      fail(
        "live games need bots for all " & $seats &
        " seats or all " & $(seats - humans) &
        " non-human seats; configured " & $bots
      )

var options* = parseGameOptions()

proc optionRunePeriod*(): int32 =
  ## The live-game rune spawn period in ticks from `--runes`.
  if options.runeSeconds < 0:
    RunePeriodTicks
  else:
    options.runeSeconds * TickRate

var
  run*: Game
  activeNetwork*: NetworkMatch
  networkActive*: bool
  localSeat* = -1

proc installGame*(newRun: Game, humanSeat = -1, networked = false) =
  ## Installs the explicitly prepared match selected by the frontend.
  run = newRun
  localSeat = humanSeat
  networkActive = networked
  activeNetwork = nil
  options.maximumTicks = newRun.maximumTicks
  options.seed = newRun.map.seed
  options.killGoal = newRun.world.killGoal
  options.botEvery = newRun.botEvery
  options.botAimNoise = newRun.botAimNoise
  options.humanSlots.setLen(0)
  if humanSeat >= 0:
    options.humanSlots.add int32(humanSeat)

proc releaseGame*() =
  ## Releases local services and clears the completed match.
  if run != nil:
    practiceFinish(run)
    hybridFinish(run)
    closeBotServices(run)
  activeNetwork = nil
  networkActive = false
  localSeat = -1
  run = nil

when not defined(emscripten):
  import duellog

  var matchLog*: DuelLogger
    ## Structured per-match analysis log; nil when logging is off.

  proc duelLoggingWanted(): bool =
    ## Captures keep only explicitly requested logs, not automatic duel logs.
    not networkActive and (options.matchLogDir.len > 0 or
      (options.duel and not options.capture.captureRequested()))

  proc duelLogBase(): string =
    if options.matchLogDir.len > 0: options.matchLogDir
    else: "duels"

  proc currentSeatScripts(): seq[string] =
    ## Bot script path per roster seat, mirroring `loadBots` seat fill;
    ## human seats stay empty.
    result = newSeq[string](run.world.pudges.len)
    var expanded: seq[string]
    for group in options.botGroups:
      for _ in 0 ..< group.count:
        expanded.add group.path
    if expanded.len == result.len:
      for i in 0 ..< result.len:
        result[i] = expanded[i]
    else:
      var next = 0
      for i in 0 ..< result.len:
        if i in run.humanSlots or next >= expanded.len:
          continue
        result[i] = expanded[next]
        inc next

  proc startDuelLogging*() =
    ## Opens a fresh match directory and logger for the current world.
    if not duelLoggingWanted():
      return
    matchLog = newDuelLogger(
      run, nextMatchDir(duelLogBase()), currentSeatScripts()
    )
    echo "duel log: ", matchLog.dir

proc closeDuelLogging*() =
  ## Finalizes the analysis log: on quit, rematch, or match end.
  when not defined(emscripten):
    if matchLog != nil:
      finishDuelLog(matchLog, run)
  else:
    discard

proc initializeGame*() =
  ## Builds an explicit command-line local match or replay.
  releaseGame()
  startGameProfile()
  var
    replayMode = options.replayPath.len > 0
    mapSeed = options.seed
    replayData: ReplayData
  if replayMode:
    profileBlock "replay":
      replayData = loadReplay(options.replayPath)
    mapSeed = replayData.header.setup.mapSeed
  var gameMap: MapData
  profileBlock "map":
    if replayMode:
      gameMap = generateMapMatching(
        mapSeed, replayData.header.setup.mapHash
      )
    elif options.duel:
      gameMap = generateMap(mapSeed, TeamSize)
    else:
      gameMap = generateMap(mapSeed, int(options.teamSize))
  let configuredTicks =
    if replayMode: int32(replayData.header.setup.maximumTicks)
    else: options.maximumTicks
  run = newGame(
    gameMap, configuredTicks, replayMode, replayData, options.killGoal,
    optionRunePeriod(), options.duel
  )
  if replayMode:
    run.maximumTicks = int32(replayData.hashes.len)
    run.replayPlayer = initReplayPlayer(replayData)
    run.historyPlayback = true
    # Controller provenance from the tape, so analysis logs label
    # human and bot seats correctly on playback.
    for i, pudge in replayData.header.setup.pudges:
      if pudge.controller == ControllerHuman:
        run.humanSlots.add i
  else:
    for slot in options.humanSlots:
      run.humanSlots.add int(slot)
    if options.humanSlots.len > 0:
      localSeat = run.humanSlots[0]
    for slot in options.pilotSlots:
      run.humanSlots.add int(slot)
    run.botEvery = max(options.botEvery, 1'i32)
    run.botAimNoise = max(options.botAimNoise, 0'i32)
    loadBots(run, options.botGroups, hybridSlots)
  if options.seatLabels.len > 0:
    applySeatLabels(run, options.seatLabels)
  elif replayMode and replayData.header.setup.seatLabels.len > 0:
    applySeatLabels(run, replayData.header.setup.seatLabels)
  when not defined(emscripten):
    startDuelLogging()

proc advanceGame*() {.measure.} =
  hybridTick(run)
  tickWorld(run, proc() = runBotDecisions(run))
  practiceTick(run)
  when not defined(emscripten):
    logDuelTick(matchLog, run)

proc beginPractice*() =
  ## Starts the decision-model coach (--practice) and pilots (--pilot)
  ## for this match. The exact action tape lands beside the trace unless
  ## --record chose another path. Multiplayer uses deterministic inputs.
  if networkActive or run.replayMode:
    return
  hybridReset()
  if not thresholdsOff:
    let table = loadThresholds(thresholdsPath)
    if table.loaded:
      echo "thresholds: ", table.path, " (default ", table.default,
        ", ", table.classes.len, " classes)"
  var matchDir = ""
  if options.practice and options.humanSlots.len > 0:
    let started = practiceBegin(run, options.practiceDir, enabled = true,
      model = options.coachModel, endpoint = options.coachEndpoint)
    if started.enabled:
      matchDir = started.dir
      echo "practice trace: ", started.dir, " (", started.provider, " ",
        started.model, ", ", started.status, ")"
  for slot in hybridSlots:
    if matchDir.len == 0: matchDir = newMatchDir(options.practiceDir)
    let adviser = hybridBegin(run, slot, matchDir, options.coachEndpoint,
      options.coachModel, hybridDelay, hybridPlan)
    echo "hybrid seat ", slot, ": ", adviser.dir
  for slot in tacticalShadowSlots:
    if matchDir.len == 0: matchDir = newMatchDir(options.practiceDir)
    let observer = hybridBegin(run, slot, matchDir, shadow = true)
    echo "tactical shadow seat ", slot, ": ", observer.dir
  for slot in options.pilotSlots:
    if matchDir.len == 0:
      matchDir = newMatchDir(options.practiceDir)
    # A headless match has no frame to keep up with, so each pilot waits
    # for its answer; the graphical client never blocks the frame.
    let pilot = pilotBegin(run, int(slot), matchDir,
      model = options.coachModel, endpoint = options.coachEndpoint,
      sync = defined(headless))
    if pilot.enabled:
      if pilotNoise > 0:
        pilot.pilotNoise(pilotNoise, int64(options.seed) * 1000 + int64(slot))
      echo "pilot seat ", slot, ": ", pilot.dir, " (", pilot.provider, " ",
        pilot.model, ", ", pilot.status,
        (if pilotNoise > 0: ", noise " & $pilotNoise else: ""), ")"
  var shadows = shadowSlots
  if shadowAll:
    for slot in 0 ..< run.world.pudges.len:
      if int32(slot) notin options.humanSlots and
          int32(slot) notin options.pilotSlots:
        shadows.add int32(slot)
  for slot in shadows:
    if int(slot) in run.humanSlots:
      echo "shadow seat ", slot, " is a human or pilot seat; skipped"
      continue
    if matchDir.len == 0:
      matchDir = newMatchDir(options.practiceDir)
    let shadow = shadowBegin(run, int(slot), matchDir)
    if shadow.enabled:
      echo "shadow seat ", slot, ": ", shadow.dir
  if matchDir.len > 0 and (options.recordPath.len == 0 or
      options.recordPath.startsWith(practiceDataDir()) or
      (options.practiceDir.len > 0 and
        options.recordPath.startsWith(options.practiceDir))):
    options.recordPath = matchDir / "replay.pwr"

proc vmStatus*(): tuple[active, decisions: int] =
  if run.replayMode:
    result.active = run.world.pudges.len
    result.decisions = run.replayPlayer.actionIndex
  else:
    for vm in run.heroVms:
      if vm != nil and not vm.failed:
        inc result.active
      if vm != nil:
        result.decisions += vm.decisions

proc startReplayRecording*(maximumTicks: uint32) =
  run.recorder = initReplayRecorder(currentSetup(run, maximumTicks))
  run.replayPlayer = ReplayPlayer(data: run.recorder.data)

proc saveRecording*() =
  ## Persists the finished tape: to --record when given, and beside
  ## the analysis log so every logged match keeps its exact replay.
  ## Keeps the original match setup; hash count is the played length.
  hybridFinish(run)
  if run.recorder == nil:
    return
  var paths: seq[string]
  if options.recordPath.len > 0:
    paths.add options.recordPath
  when not defined(emscripten):
    if matchLog != nil:
      let logCopy = matchLog.dir / "replay.pwr"
      if logCopy notin paths:
        paths.add logCopy
  if paths.len == 0:
    return
  for path in paths:
    saveReplay(path, run.recorder.data)
    echo &"replay saved: {path} " &
      &"({run.recorder.data.actions.len} actions)"

when defined(headless):
  proc printHeadlessSummary(steps: int, started: float64) =
    let
      elapsed = max(epochTime() - started, 0.000001)
      simulated = steps.float64 / TickRate.float64
      speedup = simulated / elapsed
      status = vmStatus()
      outcome =
        if run.world.gameOver:
          if run.world.winner == WestTeam: "west won" else: "east won"
        else:
          "time limit"
    echo &"result: {outcome}"
    echo &"simulated: {simulated:.2f} s in {elapsed:.4f} s " &
      &"({speedup:.1f}x real time)"
    echo &"score: west {run.world.teamKills[WestTeam.ord]} / " &
      &"east {run.world.teamKills[EastTeam.ord]}  goal {run.world.killGoal}"
    var runesTaken = 0'i32
    for pudge in run.world.pudges:
      runesTaken += pudge.runesTaken
    echo &"combat: hits {run.world.hookHits} misses {run.world.hookMisses} " &
      &"headshots {run.world.headshots} river {run.world.riverDumps} " &
      &"denies {run.world.hookDenies} runes {runesTaken}"
    echo &"hash: {run.stateHash().toHex(16)} map " &
      &"{run.map.hash.toHex(16)}"
    if run.replayMode:
      echo &"replay: {status.decisions}/{run.replayData.actions.len} actions"
    else:
      echo &"scripts: {status.active}/{run.world.pudges.len} active, " &
        &"{status.decisions} decisions"
    when not defined(emscripten):
      if matchLog != nil:
        echo &"duel log: {matchLog.dir}"

  proc runBranchHeadless() =
    ## Answer-key rollouts over the replay game built from --branch.
    var opts = branchOptions
    if opts.ticks.len == 0:
      fail("--branch needs --branch-ticks")
    if opts.slot < 0 or opts.slot >= run.world.pudges.len:
      fail("--branch-slot is outside this roster of " & $run.world.pudges.len)
    if opts.horizon <= 0:
      opts.horizon = int32(DefaultHorizonTicks)
    if opts.seeds <= 0:
      opts.seeds = 1
    if opts.botPath.len == 0:
      opts.botPath = findStockBot()
    runBranch(run, opts)

  proc runHeadless*() =
    ## Runs one explicit offline match, recording and validating its tape.
    initializeGame()
    defer: releaseGame()
    if branchOptions.path.len > 0:
      runBranchHeadless()
      return
    let
      stepLimit =
        if run.replayMode:
          run.replayData.hashes.len
        else:
          int(options.maximumTicks)
      started = epochTime()
    if not run.replayMode:
      startReplayRecording(uint32(stepLimit))
    beginPractice()
    startGameProfile()
    defer:
      finishGameProfile()
    var steps = 0
    # Headless network hybrids run on the game's wall clock. Inference never
    # freezes simulated time. Offline interventions remain accelerated.
    let realtime = hybridSlots.len > 0 and hybridPlan.len == 0 and
      coachConfig(options.coachEndpoint, options.coachModel).endpoint.len > 0
    let clockStart = getMonoTime()
    while steps < stepLimit and
        (run.replayMode or not run.world.gameOver) and
        run.recordingError.len == 0:
      if realtime:
        let remaining = int64(steps) * 1_000_000_000 div int64(TickRate) -
          (getMonoTime() - clockStart).inNanoseconds
        if remaining > 0: sleep(int((remaining + 999_999) div 1_000_000))
      advanceGame()
      inc steps
      if profileShouldDump(steps):
        finishGameProfile()
    practiceFinish(run)
    hybridFinish(run)
    if run.recordingError.len > 0:
      raise newException(ReplayError, run.recordingError)
    closeDuelLogging()
    if run.replayMode:
      run.hashCheck.requireReplayComplete(
        uint32(run.world.tick),
        run.replayData.hashes.len
      )
      if not run.replayPlayer.finished:
        raise newException(
          ReplayError,
          "replay simulation did not consume every action"
        )
      echo "replay verified: every tick matched"
    else:
      saveRecording()
    printHeadlessSummary(steps, started)
