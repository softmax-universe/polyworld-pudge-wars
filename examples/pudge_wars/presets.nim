import
  std/json,
  jsony,
  polyworld/rooms,
  content

const
  MaxMatchTicks* = TickRate * 60 * 60
  StockBotSource* = staticRead("players/base.bas")
  BotPolicies* = [
    ("Base", StockBotSource),
    ("Aggressive", staticRead("players/aggressive.bas")),
    ("Patient", staticRead("players/patient.bas")),
    ("Sniper", staticRead("players/sniper.bas")),
    ("Support", staticRead("players/support.bas")),
    ("Denier", staticRead("players/denier.bas"))
  ]

type
  MatchConfig* = object
    seed*, maxTicks*: int32
    teamSize*: int
    killGoal*, botEvery*, botAimNoise*, runePeriod*: int32
  BotDifficulty* = enum
    Easy, Fair, Pro

proc setDifficulty*(config: var MatchConfig, difficulty: BotDifficulty) =
  ## Uses the same decision cadence and aim scatter as the CLI.
  case difficulty
  of Easy:
    config.botEvery = 16
    config.botAimNoise = 2
  of Fair:
    config.botEvery = 8
    config.botAimNoise = 1
  of Pro:
    config.botEvery = 1
    config.botAimNoise = 0

proc defaultConfig*(): MatchConfig =
  ## Uses the standard arena, timer, and bot settings for a new lobby.
  MatchConfig(
    seed: 2026, maxTicks: 20 * 60 * TickRate, teamSize: TeamSize,
    killGoal: KillGoal, botEvery: 1, runePeriod: RunePeriodTicks
  )

proc validate*(config: MatchConfig) =
  ## Bounds settings before generating the arena or compiling policies.
  if config.teamSize notin 1 .. MaxTeamSize:
    reject("Pudge Wars supports one to five seats per bank")
  if config.maxTicks notin 1 .. MaxMatchTicks or config.killGoal < 1:
    reject("Invalid Pudge Wars time limit or kill goal")
  if config.botEvery < 1 or config.botAimNoise notin 0 .. 128 or
    config.runePeriod < 0:
      reject("Invalid Pudge Wars bot or rune settings")

proc seatEnabled*(config: MatchConfig, seat: int): bool =
  ## Keeps East's lobby addresses fixed when the configured banks resize.
  seat in 0 ..< MaxPudgeCount and seat mod MaxTeamSize < config.teamSize

proc validateRoster*(config: MatchConfig, seats: openArray[Seat]) =
  ## Requires the fixed bank layout and at least one occupied slot per side.
  config.validate()
  if seats.len != MaxPudgeCount:
    reject("Pudge Wars rooms need ten stable bank slots")
  var occupied: array[Team, bool]
  for i, seat in seats:
    if seat.owner == 0:
      continue
    if not config.seatEnabled(i):
      reject("Release occupied seats outside the selected bank size")
    occupied[Team(i div MaxTeamSize)] = true
  if not occupied[WestTeam] or not occupied[EastTeam]:
    reject("Place at least one butcher on each bank")

proc encodeConfig*(config: MatchConfig): string =
  ## Writes only the public match settings into the shared room payload.
  config.validate()
  config.toJson()

proc parseConfig*(payload: string): MatchConfig =
  ## Requires a complete, version-compatible set of integer settings.
  if payload.len > MaxPayloadBytes:
    reject("Pudge Wars room settings exceed the payload limit")
  var node: JsonNode
  try:
    node = parseJson(payload)
  except JsonParsingError as error:
    reject("Invalid Pudge Wars room settings: " & error.msg)
  if node.kind != JObject:
    reject("Pudge Wars room settings must be an object")
  proc number(name: string): int32 =
    ## Reads one required field without coercing strings or decimals.
    let field = node{name}
    if field == nil or field.kind != JInt or
      field.getBiggestInt() notin int64(int32.low) .. int64(int32.high):
        reject("Invalid Pudge Wars room setting: " & name)
    field.getBiggestInt().int32
  result = MatchConfig(
    seed: number("seed"), maxTicks: number("maxTicks"),
    teamSize: int(number("teamSize")), killGoal: number("killGoal"),
    botEvery: number("botEvery"), botAimNoise: number("botAimNoise"),
    runePeriod: number("runePeriod")
  )
  result.validate()
