## Chat shares the ordered action tape through playback and repeated seeks.

import
  polyworld/tapes,
  ../examples/pudge_wars/[content, maps, replays, sim]

const RecordedTicks = 4'i32

proc freshGame(): Game =
  ## Creates an offline recorder without loading a private bot runtime.
  result = newGame(generateMap(2026), RecordedTicks, false, ReplayData())
  result.recorder = initReplayRecorder(
    result.currentSetup(uint32(RecordedTicks)))
  result.replayPlayer = ReplayPlayer(data: result.recorder.data)

proc finishHeroTurn(game: Game) =
  ## Advances the same deterministic rotation used by normal hero turns.
  game.world.heroTurnStart =
    (game.world.heroTurnStart + 1) mod game.world.pudges.len

proc recordAction(game: Game, kind: uint8, first = 0'i32,
    second = 0'i32) =
  ## Records and executes a resolved action at the current simulation tick.
  let action = ReplayAction(
    tick: uint32(game.world.tick),
    pudgeId: game.world.pudges[0].id,
    kind: kind, first: first, second: second
  )
  game.recorder.record(action)
  game.world.applyReplayAction(action)

proc chat(game: Game, text: string): MatchChatLine =
  ## Identifies the same speaker independently of replay cursor position.
  MatchChatLine(
    tick: game.world.tick, slot: 0, name: "Arena player", text: text,
    team: int32(game.world.pudges[0].team.ord)
  )

proc texts(game: Game): seq[string] =
  ## Reads the displayed projection without introducing a second tape cursor.
  for line in game.chatLog:
    result.add line.text

proc noBotDecisions() =
  ## Fails if playback tries to recreate commands through a live policy.
  doAssert false, "Replay must consume recorded inputs without running bots"

proc rejects(data: ReplayData) =
  ## Requires malformed chat entries to fail before replay is accepted.
  try:
    data.validate()
    doAssert false, "Invalid replay chat was accepted"
  except ReplayError:
    discard

echo "Testing same-tick action, chat, action round trip"
let live = freshGame()
var snapshots = @[live.world.clone()]
for tick in 1 .. RecordedTicks:
  live.tickWorld(proc() =
    ## Interleaves display messages and physical commands in recording order.
    if live.world.tick == 1:
      live.recordAction(ActionWalkTo, 30, 64)
      live.recordChat(live.chat("Moving first"))
      live.recordAction(ActionStop)
    elif live.world.tick == 2:
      live.recordChat(live.chat("Holding position"))
    elif live.world.tick == 3:
      live.recordAction(ActionRotToggle)
      live.recordChat(live.chat("Rot toggled twice"))
      live.recordAction(ActionRotToggle)
    live.finishHeroTurn()
  )
  snapshots.add live.world.clone()

let
  encoded = live.recorder.data.encodeReplay()
  decoded = decodeReplay(encoded)
doAssert decoded.header.formatVersion == ReplayFormatVersion
doAssert decoded.header.gameVersion == ReplayGameVersion
doAssert decoded.actions == live.recorder.data.actions
doAssert decoded.hashes == live.recorder.data.hashes
doAssert decoded.actions.len == 7
doAssert decoded.actions[0].kind == ActionWalkTo
doAssert decoded.actions[1].kind == ActionChat
doAssert decoded.actions[2].kind == ActionStop
doAssert decoded.actions[0].tick == 1 and decoded.actions[2].tick == 1
doAssert decoded.actions[1].tick == 1
doAssert decoded.actions[1].pudgeId == live.world.pudges[0].id
doAssert decoded.actions[1].first == 0
doAssert decoded.actions[1].second == int32(WestTeam.ord)
doAssert decoded.actions[1].name == "Arena player"
doAssert decoded.actions[1].text == "Moving first"
doAssert decoded.actions[3].kind == ActionChat
doAssert decoded.actions[4].kind == ActionRotToggle
doAssert decoded.actions[5].kind == ActionChat
doAssert decoded.actions[6].kind == ActionRotToggle
doAssert live.texts() == @[
  "Moving first", "Holding position", "Rot toggled twice"
]

echo "Testing chat playback preserves hashes without private runtimes"
let playback = newGame(live.map, RecordedTicks, true, decoded)
playback.replayPlayer = initReplayPlayer(decoded)
playback.historyPlayback = true
for tick in 1 .. RecordedTicks:
  playback.tickWorld(noBotDecisions)
  doAssert playback.stateHash() == decoded.hashes[tick - 1]
  doAssert playback.chatLog.len == min(int(tick), 3)
  doAssert playback.heroVms.len == 0
doAssert playback.chatLog == live.chatLog
doAssert playback.hashCheck.mismatches == 0
doAssert playback.replayPlayer.finished

echo "Testing backward and forward seeks rebuild chat exactly once"
for target in [1, 0, 3, 1]:
  playback.world.restore(snapshots[target])
  playback.restoreReplayCursor()
  doAssert playback.chatLog.len == min(target, 3)
  if target >= 1:
    doAssert playback.chatLog[0].text == "Moving first"
  while playback.world.tick < RecordedTicks:
    playback.tickWorld(noBotDecisions)
  doAssert playback.chatLog == live.chatLog,
    "Seeking must neither duplicate messages nor preserve future chat"
  doAssert playback.stateHash() == decoded.hashes[^1]
  doAssert playback.hashCheck.mismatches == 0
  doAssert playback.replayPlayer.finished

echo "Testing live history never appends replayed chat to its recording"
let recordedActions = live.recorder.data.actions
live.world.restore(snapshots[1])
live.historyPlayback = true
live.restoreReplayCursor()
doAssert live.texts() == @["Moving first"]
while live.world.tick < RecordedTicks:
  live.tickWorld(noBotDecisions)
doAssert live.chatLog == playback.chatLog
doAssert live.recorder.data.actions == recordedActions
doAssert live.recorder.data.hashes == decoded.hashes

echo "Testing a live seek restores later controller handoffs"
block:
  let controlled = freshGame()
  controlled.humanSlots = @[0]
  controlled.recorder = initReplayRecorder(
    controlled.currentSetup(uint32(RecordedTicks)))
  controlled.replayPlayer = ReplayPlayer(data: controlled.recorder.data)
  let beginning = controlled.world.clone()
  for tick in 1 .. RecordedTicks:
    controlled.tickWorld(proc() =
      ## Records a human takeover after the restored checkpoint.
      if controlled.world.tick == 2:
        controlled.recorder.recordTakeOver(2,
          controlled.world.pudges[1].id, ControllerHuman)
        controlled.humanSlots.add 1
      controlled.finishHeroTurn()
    )
  doAssert controlled.humanSlots == @[0, 1]
  controlled.world.restore(beginning)
  controlled.historyPlayback = true
  controlled.restoreReplayCursor()
  doAssert controlled.humanSlots == @[0]
  while controlled.world.tick < RecordedTicks:
    controlled.tickWorld(noBotDecisions)
    if controlled.world.tick >= 2:
      doAssert controlled.humanSlots == @[0, 1],
        "Crossing a recorded handoff must restore live human control"
  doAssert controlled.hashCheck.mismatches == 0

echo "Testing local UI chat is admitted at the next simulation tick"
block:
  let queued = freshGame()
  doAssert queued.queueChat(queued.chat("Waiting for a tick"))
  doAssert queued.chatLog.len == 0
  doAssert queued.recorder.data.actions.len == 0
  queued.tickWorld(proc() =
    ## Orders queued chat before the next tick's physical commands.
    queued.recordAction(ActionStop)
    queued.finishHeroTurn()
  )
  doAssert queued.recorder.data.actions.len == 2
  doAssert queued.recorder.data.actions[0].kind == ActionChat
  doAssert queued.recorder.data.actions[0].tick == 1
  doAssert queued.recorder.data.actions[1].kind == ActionStop
  doAssert queued.texts() == @["Waiting for a tick"]
  queued.historyPlayback = true
  doAssert not queued.queueChat(queued.chat("Cannot rewrite history"))
  doAssert queued.recorder.data.actions.len == 2
  doAssert not playback.queueChat(playback.chat("Replay cannot send"))

echo "Testing malformed replay chat fails validation"
block:
  var invalid = decodeReplay(encoded)
  invalid.actions[1].text = "bad\nline"
  invalid.rejects()
  invalid = decodeReplay(encoded)
  invalid.actions[1].text = "\xff"
  invalid.rejects()
  invalid = decodeReplay(encoded)
  invalid.actions[1].first = -2
  invalid.rejects()
  invalid = decodeReplay(encoded)
  invalid.actions[1].second = 2
  invalid.rejects()

echo "Pudge Wars ordered chat replay, seeks, hashes and admission passed"
