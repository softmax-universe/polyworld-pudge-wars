## Human pacing changes wall time, never fixed-step simulation outcomes.
import std/[times, unittest],
  polyworld/player,
  ../examples/pudge_wars/[maps, pacing, replays, sim]

proc oneSecond(humanPaced: bool): int32 =
  var transport = initPlayer(live = true, durationTicks = 1000)
  # Include a microsecond of tolerance at the one-second boundary: 1/28
  # cannot be represented exactly by the transport's float32 accumulator.
  for frame in 0 .. 64:
    let dt = if frame == 64: 0.000001'f32 else: 1.0'f32 / 64
    transport.startFrame(dt, wallTickRate(humanPaced))
    while transport.shouldTick(epochTime()):
      inc transport.tick
      transport.recordedTicks = transport.tick
  transport.tick

suite "human clock":
  test "one wall second advances 28 human ticks or 32 bot ticks":
    check oneSecond(true) == 28
    check oneSecond(false) == 32
    check wallTickNanoseconds(true) == 35_714_285
    check wallTickNanoseconds(false) == 31_250_000

  test "the same ticks still produce the same physics and hashes":
    let map = generateMap(7)
    let normal = newGame(map, 100, false, ReplayData())
    let slow = newGame(map, 100, false, ReplayData())
    slow.humanPaced = true
    for tick in 0 ..< 64:
      tickWorld(normal, proc() = discard)
      tickWorld(slow, proc() = discard)
      check stateHash(normal) == stateHash(slow)
