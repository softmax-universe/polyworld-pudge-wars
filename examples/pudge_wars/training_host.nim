## Headless JSONL access to the local simulation and fog-filtered player view.

import std/[json, strutils]
import pudgewars/cli
import content, maps, sim, bots, replays
import observations

var
  learnerSlot: int
  game: Game
  receipt: ObservationEcho

proc snapshot(): JsonNode =
  ## Report the learner's current view and whether the episode has ended.
  let final = game.world.gameOver or game.world.tick >= game.maximumTicks
  %*{
    "observation": observation(game, learnerSlot, receipt, final),
    "done": final
  }

proc handle(request: JsonNode): JsonNode =
  ## Reset or advance the local learner episode.
  case request["kind"].getStr
  of "reset":
    let
      seats = request["seats"].getInt
      seed = int32(request["seed"].getInt)
    if seats < 2 or seats > MaxPudgeCount or seats mod 2 != 0:
      raise newException(ValueError, "Pudge Wars needs 2, 4, 6, 8, or 10 seats")
    learnerSlot = request["learner_slot"].getInt
    if learnerSlot < 0 or learnerSlot >= seats:
      raise newException(ValueError, "Learner slot is outside the roster")
    let maxTicks = request["max_ticks"].getBiggestInt
    if maxTicks < 1 or maxTicks > high(int32):
      raise newException(ValueError, "max_ticks must be a positive int32")
    receipt = ObservationEcho()
    let teamSize = if seats == DuelPudgeCount: TeamSize else: seats div 2
    game = newGame(
      generateMap(seed, teamSize), int32(maxTicks), false, ReplayData(),
      if seats == DuelPudgeCount: DuelKillGoal else: KillGoal,
      RunePeriodTicks, seats == DuelPudgeCount
    )
    game.humanSlots = @[learnerSlot]
    loadBots(game, [BotGroup(
      path: "examples/pudge_wars/players/base.bas", count: seats - 1
    )])
    snapshotAccepted(game, receipt)
    game.intentResults.setLen(0)
    result = snapshot()
  of "step":
    if request["tick"].getInt != game.world.tick:
      raise newException(ValueError, "Action belongs to another tick")
    applyAction(game, receipt, learnerSlot, request["action"])
    tickWorld(game, proc() = runBotDecisions(game))
    snapshotAccepted(game, receipt)
    game.intentResults.setLen(0)
    result = snapshot()
  else:
    raise newException(ValueError, "Unknown training host command")

for line in stdin.lines:
  if line.strip.len > 0:
    echo $handle(parseJson(line))
