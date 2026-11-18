## Check that a recording made with JSON actions replays with the same hashes.

import
  std/[json, strutils],
  polyworld/tapes,
  ../examples/pudge_wars/maps,
  ../examples/pudge_wars/bots,
  ../examples/pudge_wars/replays,
  ../examples/pudge_wars/observations,
  ../examples/pudge_wars/sim

const Ticks = 120'i32

let map = generateMap(7)

proc recordingGame(): Game =
  ## Create a recording with all six seats controlled by JSON actions.
  result = newGame(map, Ticks, false, ReplayData(), killGoal = 3)
  result.humanSlots.setLen(0)
  for i in 0 ..< result.world.pudges.len:
    result.humanSlots.add i
  result.recorder = initReplayRecorder(currentSetup(result, uint32(Ticks)))
  result.replayPlayer = ReplayPlayer(data: result.recorder.data)

proc replayGame(setup: Setup): Game =
  ## Rebuild the world from the setup recorded in the tape.
  result = Game(
    world: newWorld(map, Ticks, setup.pudges, setup.killGoal, setup.runePeriod),
    map: map,
    maximumTicks: Ticks,
    botEvery: 1,
    historyPlayback: true,
    replayPlayer: ReplayPlayer(data: initReplayData(setup)),
  )

echo "Testing JSON-action recording and replay hashes"
block:
  let recorded = recordingGame()
  var receipt: ObservationEcho
  for tick in 1'i32 .. Ticks:
    if tick == 4:
      applyAction(recorded, receipt, 1, %*{"walk_to": [90, 64]})
      applyAction(recorded, receipt, 4, %*{"walk_to": [40, 64]})
    if tick == 6:
      applyAction(recorded, receipt, 2, %*{"walk_to": [88, 70]})
    if tick == 8:
      applyAction(recorded, receipt, 2, %*{"hook_to": [64, 64]})
      applyAction(recorded, receipt, 5, %*{"hook_to": [64, 60]})
    tickWorld(recorded, proc() = runBotDecisions(recorded))
    snapshotAccepted(recorded, receipt)
    recorded.intentResults.setLen(0)

  let decoded = decodeReplay(encodeCoworldReplay(recorded.recorder.data))
  let playback = replayGame(decoded.header.setup)
  playback.replayPlayer.data = decoded
  var firstBad = -1
  for tick in 1'i32 .. Ticks:
    tickWorld(playback, proc() = discard)
    var expected: uint64
    if decoded.hashes.hashAt(uint32(tick), expected):
      if stateHash(playback) != expected and firstBad < 0:
        firstBad = tick
        echo "  DIVERGE at tick ", tick,
          " recorded=", expected.toHex(16), " replay=", stateHash(playback).toHex(16)
  doAssert firstBad < 0,
    "JSON-action recording diverged from its replay at tick " & $firstBad
  doAssert recorded.recordingError.len == 0, recorded.recordingError
  doAssert decoded.header.setup.maximumTicks == uint32(Ticks)
  doAssert decoded.hashes.len == Ticks
  doAssert decoded.actions.len == recorded.recorder.data.actions.len

echo "test_pw_observation_replay: all checks passed"
