## Shared CLI flags used by the graphical client.

import
  std/[os, osproc, strutils],
  pudgewars/cli

proc parseCommon(arguments: seq[string]): GameOptions =
  ## Parses only shared flags, the same way the game loop would.
  result = GameOptions()
  result.seed = 2026
  result.tickRate = 32
  var index = 0
  while index < arguments.len:
    let argument = arguments[index]
    if not result.takeCommonFlag(arguments, index, argument):
      doAssert false, "unexpected argument: " & argument
    inc index

if paramCount() > 0 and paramStr(1) == "--capture-validation-child":
  let options = parseCommon(commandLineParams()[1 .. ^1])
  options.validateGameOptions(0, "")
  quit(0)

proc validateChild(arguments: seq[string]): tuple[output: string, exitCode: int] =
  ## Exercises CLI failures without allowing quit to terminate the test runner.
  var command = quoteShell(getAppFilename()) & " --capture-validation-child"
  for argument in arguments:
    command.add " " & quoteShell(argument)
  execCmdEx(command)

echo "Testing the shared screenshot arguments"
block:
  let defaults = parseCommon(@[])
  doAssert defaults.capture.path.len == 0
  doAssert defaults.capture.frames == 30
  doAssert not defaults.capture.framesSpecified
  for arguments in [
    @["--screenshot", "capture folder/menu.png", "--frames", "3"],
    @["--screenshot=capture folder/menu.png", "--frames=3"],
    @["--screenshot:capture folder/menu.png", "--frames:3"]
  ]:
    let options = parseCommon(arguments)
    doAssert options.capture.path == "capture folder/menu.png"
    doAssert options.capture.frames == 3
    doAssert options.capture.framesSpecified
    doAssert options.capture.captureRequested()
  let windows = parseCommon(@[r"--screenshot:C:\captures\menu.png"])
  doAssert windows.capture.path == r"C:\captures\menu.png"
  let successful = validateChild(@["--screenshot", "menu.png"])
  if defined(headless) or defined(emscripten):
    doAssert successful.exitCode != 0
    doAssert "native graphical client" in successful.output
  else:
    doAssert successful.exitCode == 0, successful.output
  for arguments in [
    @["--screenshot"], @["--screenshot="],
    @["--screenshot", "--frames", "3"],
    @["--frames", "0"], @["--frames=-1"],
    @["--frames:invalid"], @["--frames=2147483648"],
    @["--windowSize", "0x600"], @["--windowSize=800x"],
    @["--windowSize", "--frames", "3"]
  ]:
    let rejected = validateChild(arguments)
    doAssert rejected.exitCode != 0, $arguments & " must be rejected"
    doAssert rejected.output.len > 0

echo "Testing --vsync is on by default"
block:
  let options = parseCommon(@[])
  doAssert options.vsync
  let off = parseCommon(@["--vsync:off"])
  doAssert not off.vsync
  let on = parseCommon(@["--vsync=on"])
  doAssert on.vsync
  let split = parseCommon(@["--vsync", "off"])
  doAssert not split.vsync
  let splitOn = parseCommon(@["--vsync", "on"])
  doAssert splitOn.vsync

echo "Testing --windowSize is a shared flag"
block:
  let options = parseCommon(@["--windowSize:800x400"])
  doAssert options.windowWidth == 800
  doAssert options.windowHeight == 400
  let split = parseCommon(@["--windowSize", "1024x576"])
  doAssert split.windowWidth == 1024
  doAssert split.windowHeight == 576
  let equals = parseCommon(@["--windowSize=1280x720"])
  doAssert equals.windowWidth == 1280
  doAssert equals.windowHeight == 720

echo "Testing --windowPos places the window"
block:
  let unset = parseCommon(@[])
  doAssert unset.windowX == -1 and unset.windowY == -1
  let colon = parseCommon(@["--windowPos:400,80"])
  doAssert colon.windowX == 400 and colon.windowY == 80
  let split = parseCommon(@["--windowPos", "0,25"])
  doAssert split.windowX == 0 and split.windowY == 25
  let equals = parseCommon(@["--windowPos=1200,600"])
  doAssert equals.windowX == 1200 and equals.windowY == 600

echo "Testing shared replay, bot, and player spellings"
block:
  for arguments in [
    @["--bots", "bots/base.bas:2", "--bot", "bots/other.bas",
      "--record", "replay folder/match.pwr", "--player", "2", "--name", "Ada"],
    @["--bots=bots/base.bas:2", "--bot=bots/other.bas",
      "--record=replay folder/match.pwr", "--player=2", "--name=Ada"],
    @["--bots:bots/base.bas:2", "--bot:bots/other.bas",
      "--record:replay folder/match.pwr", "--player:2", "--name:Ada"]
  ]:
    var options = parseCommon(arguments)
    doAssert options.botGroups.botCount == 3
    doAssert options.recordPath == "replay folder/match.pwr"
    doAssert options.playerSlot == 2 and options.playerName == "Ada"
    options.configurePlayerSlot()
    doAssert options.humanSlots == @[1'i32]
    when not defined(headless):
      options.validateGameOptions(4, "four seats")
  doAssert parseCommon(@["--player"]).playerSlot == 1
  for arguments in [
    @["--replay", "replay folder/match.pwr"],
    @["--replay=replay folder/match.pwr"],
    @["--replay:replay folder/match.pwr"]
  ]:
    doAssert parseCommon(arguments).replayPath == "replay folder/match.pwr"

echo "Testing actual game tick rate and shared runtime options"
block:
  for argument in ["--minutes=1", "--minutes:1"]:
    let options = parseCommon(@[argument])
    doAssert options.maximumTicks == 60 * 32
    doAssert options.seconds == 60
  let options = parseCommon(@["--seconds", "2", "--speed:4", "--play:false",
    "--seed:9", "--mute", "--unmute", "--headless-tick-rate:16",
    "--llm-mode=barrier", "--server:ws://localhost:9911/ws", "--room", "ABCD"])
  doAssert options.maximumTicks == 64 and options.seconds == 2
  doAssert options.speed == 4 and options.pauseOnStart and options.seed == 9
  doAssert options.soundOverride and not options.soundMuted
  doAssert options.headlessTickRate == 16 and options.waitForLlm
  doAssert options.serverUrl == "ws://localhost:9911/ws"
  doAssert options.roomCode == "ABCD"

echo "Testing shared paths and practice seats"
block:
  var options = parseCommon(@["--player=2", "--bot", "bots/base.bas:2",
    "--record", "nested/match.pwr"])
  options.addPracticePlayer("3")
  options.configurePlayerSlot()
  doAssert options.humanSlots == @[1'i32, 2'i32]
  options.resolveGamePaths()
  doAssert options.recordPath == absolutePath("nested/match.pwr")
  doAssert options.botGroups[0].path == absolutePath("bots/base.bas")
  var rejected = false
  try:
    options.addPracticePlayer("0")
  except ValueError:
    rejected = true
  doAssert rejected
  rejected = false
  try:
    options.addPracticePlayer("2")
  except ValueError:
    rejected = true
  doAssert rejected

echo "Testing invalid common flag values"
block:
  for arguments in [
    @["--record", "--replay", "match.pwr"],
    @["--bot:base.bas:0"], @["--bots=base.bas:2147483648"],
    @["--player", "Ada"], @["--player:0"], @["--name="],
    @["--replay", "a.pwr", "--record", "b.pwr"],
    @["--replay", "a.pwr", "--bot", "base.bas"]
  ]:
    var rejected = false
    try:
      let options = parseCommon(arguments)
      options.validateGameOptions(0, "")
    except ValueError:
      rejected = true
    doAssert rejected, "Invalid common launch must fail: " & $arguments

echo "Testing network launch exclusivity and retained recording settings"
block:
  for network in ["--server=ws://localhost:9911/ws", "--room:ABCD"]:
    for local in ["--bot=base.bas:2", "--player:2", "--replay=match.pwr"]:
      var rejected = false
      try:
        parseCommon(@[network, local]).validateGameOptions(0, "")
      except ValueError:
        rejected = true
      doAssert rejected, "Network launch must not ignore " & local
    let options = parseCommon(@[network, "--record=nested/match.pwr",
      "--name=Player"])
    when not defined(headless):
      options.validateGameOptions(0, "")
    else:
      var rejected = false
      try:
        options.validateGameOptions(0, "")
      except ValueError:
        rejected = true
      doAssert rejected, "Headless launches cannot use a display name"
    doAssert options.recordPath == "nested/match.pwr"
    doAssert options.playerName == "Player"
  when not defined(headless):
    var rejected = false
    try:
      parseCommon(@["--headless-tick-rate=0"]).validateGameOptions(0, "")
    except ValueError:
      rejected = true
    doAssert rejected

echo "test_pw_cli: all checks passed"
