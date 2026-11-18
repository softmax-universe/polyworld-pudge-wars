import
  std/[os, tempfiles],
  pudgewars/cli,
  ../examples/pudge_wars/[frontend, game, replays, sim]

proc checkRematch() =
  ## Drives two real CLI matches through the frontend's presentation loop.
  let folder = createTempDir("pudge-rematch-", "")
  defer:
    removeDir(folder)
  let
    recording = folder / "record.pwr"
    trace = folder / "practice.pwr"
  if options.recordPath.len > 0:
    doAssert directPlay
    doAssert options.botGroups.len > 0
  options.recordPath = recording
  options.matchLogDir = folder / "logs"
  options.maximumTicks = 16
  options.teamSize = 1
  options.humanSlots = @[0'i32]
  options.botGroups = @[]
  options.botGroups.addBotSpec(currentSourcePath().parentDir.parentDir /
    "examples/pudge_wars/players/base.bas:2")
  var
    matches: int
    initialHash: uint64
    previous: Game
    logs: seq[string]
  runDirectMatches(proc(): bool =
    ## Requests one rematch after recording a short run without opening a UI.
    inc matches
    doAssert run.world.tick == 0
    doAssert localSeat == 0
    doAssert options.recordPath == recording
    doAssert vmStatus().active == 2
    if matches == 1:
      initialHash = run.stateHash()
      previous = run
      options.recordPath = trace
    else:
      doAssert run != previous
      doAssert run.stateHash() == initialHash
      doAssert fileExists(logs[0] / "summary.json")
    logs.add matchLog.dir
    startReplayRecording(uint32(options.maximumTicks))
    for _ in 0 ..< matches * 2:
      advanceGame()
    saveRecording()
    matches == 2
  )
  doAssert matches == 2
  doAssert run == nil and localSeat == -1
  doAssert options.recordPath == recording
  doAssert logs[0] != logs[1]
  doAssert fileExists(logs[1] / "summary.json")
  doAssert loadReplay(trace).hashes.len == 2
  doAssert loadReplay(recording).hashes.len == 4
  for log in logs:
    doAssert fileExists(log / "replay.pwr")

echo "Direct Pudge matches rematch with fresh state, logs, and recordings"
checkRematch()
