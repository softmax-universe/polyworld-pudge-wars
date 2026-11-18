## Run one staged BASIC episode and write local artifacts.

import
  std/[json, os],
  content, maps, sim, bots, replays, fileplayers

type EpisodeConfig = object
  names: seq[string]
  seed, maxTicks, killGoal: int32
  waitForLlm: bool

proc parseConfig(node: JsonNode): EpisodeConfig =
  ## Validate the staged episode configuration before opening any outputs.
  if node.kind != JObject or node{"players"}.isNil or
      node["players"].kind != JArray or
      node{"seed"}.isNil or node["seed"].kind != JInt or
      node["seed"].getBiggestInt < low(int32) or
      node["seed"].getBiggestInt > high(int32) or
      node{"max_ticks"}.isNil or node["max_ticks"].kind != JInt or
      node["max_ticks"].getBiggestInt notin 1'i64 .. 40000'i64 or
      node{"kill_goal"}.isNil or node["kill_goal"].kind != JInt or
      node["kill_goal"].getBiggestInt notin 1'i64 .. 40'i64 or
      not node{"fog"}.getBool(true):
    raise newException(FilePlayerError, "Invalid BASIC episode configuration")
  let count = node["players"].len
  if count < DuelPudgeCount or count > MaxPudgeCount or count mod 2 != 0:
    raise newException(FilePlayerError, "Pudge Wars needs 2, 4, 6, 8, or 10 seats")
  for player in node["players"]:
    let name = player{"name"}.getStr
    if name.len == 0:
      raise newException(FilePlayerError, "Each BASIC seat needs a name")
    result.names.add name
  result.seed = int32(node["seed"].getBiggestInt)
  result.maxTicks = int32(node["max_ticks"].getBiggestInt)
  result.killGoal = int32(node["kill_goal"].getBiggestInt)
  result.waitForLlm = node{"wait_for_llm"}.getBool(true)

proc stagedPath(variable: string): string =
  ## Resolve a required runner environment variable to a local file.
  let value = getEnv(variable)
  if value.len == 0:
    raise newException(FilePlayerError, variable & " is required")
  localPath(value)

proc resultsJson(game: Game, seed: int32): JsonNode =
  ## Report the final scores and per-seat results for a staged episode.
  let world = game.world
  var scores = newJArray()
  var perSeat = newJArray()
  let
    west = world.teamKills[WestTeam.ord]
    east = world.teamKills[EastTeam.ord]
  for i, pudge in world.pudges:
    let
      mine = if pudge.team == WestTeam: west else: east
      theirs = if pudge.team == WestTeam: east else: west
    # Win or fail per seated agent: 1 if that bank is ahead, else 0 (draws fail).
    scores.add %(if mine > theirs: 1.0 else: 0.0)
    perSeat.add %*{
      "slot": i,
      "team": pudge.team.ord,
      "kills": pudge.kills,
      "deaths": pudge.deaths,
      "hooks_thrown": pudge.hooksThrown,
      "hooks_landed": pudge.hooksLanded
    }
  let reason =
    if world.gameOver: "kill_goal"
    else: "time_limit"
  var winner = "draw"
  if west > east:
    winner = "west"
  elif east > west:
    winner = "east"
  if world.gameOver:
    winner = if world.winner == WestTeam: "west" else: "east"
  %*{
    "scores": scores,
    "winner_team": winner,
    "west_kills": west,
    "east_kills": east,
    "end_tick": world.tick,
    "end_reason": reason,
    "seed": seed,
    "kill_goal": world.killGoal,
    "per_seat": perSeat
  }

proc runEpisode(): int =
  ## Complete one match and publish results after the replay and private outputs.
  let
    config = parseJson(readFile(stagedPath("COGAME_CONFIG_URI"))).parseConfig()
    resultsPath = stagedPath("COGAME_RESULTS_URI")
    replayPath = stagedPath("COGAME_SAVE_REPLAY_URI")
    rosterPath = stagedPath("COGAME_PLAYER_SEATS_URI")
    failureUri = getEnv("COGAME_PLAYER_FAILURE_URI")
    count = config.names.len
    duel = count == DuelPudgeCount
    teamSize = if duel: TeamSize else: count div 2
    game = newGame(
      generateMap(config.seed, teamSize),
      config.maxTicks,
      false,
      ReplayData(),
      config.killGoal,
      RunePeriodTicks,
      duel
    )
  applySeatLabels(game, config.names)
  echo "episode map seed=", config.seed, " seats=", count, " kill_goal=",
    game.world.killGoal, " max_ticks=", config.maxTicks
  let seats = openFilePlayers(parseJson(readFile(rosterPath)), count, failureUri)
  if not seats.load(game):
    return 2
  game.recorder = initReplayRecorder(currentSetup(game, uint32(config.maxTicks)))
  game.replayPlayer = ReplayPlayer(data: game.recorder.data)
  while game.world.tick < config.maxTicks and not game.world.gameOver and
      game.recordingError.len == 0:
    tickWorld(game, proc() = runBotDecisions(game))
    if config.waitForLlm:
      game.waitForBotRequests()
    seats.captureErrors(game)
  if game.recordingError.len > 0:
    raise newException(FilePlayerError, "Replay recording failed")
  let replay = encodeCoworldReplay(game.recorder.data)
  seats.finish(game)
  writeAtomic(replayPath, replay)
  writeAtomic(resultsPath, $resultsJson(game, config.seed))

quit(runEpisode())
