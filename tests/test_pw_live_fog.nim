import
  std/os,
  pudgewars/cli,
  ../examples/pudge_wars/[bots, content, fog, maps, replays, sim]

const BotPath = currentSourcePath().parentDir.parentDir /
  "examples/pudge_wars/players/base.bas"

echo "Testing live hook fog preserves legacy rounding at int64 limits"
let game = newGame(generateMap(2026), 1024, false, ReplayData())
game.humanSlots = @[0]
game.loadBots([BotGroup(path: BotPath, count: PudgeCount)])
var vision: seq[uint8]
for tick in 1 .. 1024:
  game.tickWorld(proc() = game.runBotDecisions())
  let before = game.stateHash()
  for team in Team:
    game.world.fillTeamVision(team.ord, vision)
    doAssert vision.len == 128 * 128
    doAssert game.stateHash() == before
game.closeBotServices()
doAssert game.world.tick == 1024
echo "test_pw_live_fog: all checks passed"
