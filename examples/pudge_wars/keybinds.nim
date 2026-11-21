## Rebindable keys for the human seat.
##
## Defaults match the research doc's layout (Q hook, E grapple, F blink,
## R rot, X stop, G ping, Option-click ping, F1 center, L follow,
## T take-over, 1-4 upgrades, M mute, R rematch on the end screen).
## Hold C and move the pointer to pan (trackpad camera grab); tap C
## still arms a wall. L locks the camera on your butcher.
## A plain-text file overrides them, one `action = KeyName` per line,
## using windy button names such as KeyQ or KeyF1:
##
##   hook = KeyD
##   center = KeySpace
##   pan = KeySpace
##   director = KeyY
##   quickcast = on
##   autocast = on
##
## Unknown actions or key names warn and keep the default, so a typo
## never bricks the seat. `quickcast` / `autocast` are on/off settings,
## not keys.

import std/[os, strutils], windy

type
  BindAction* = enum
    BindHook = "hook"
    BindGrapple = "grapple"
    BindBlink = "blink"
    BindRot = "rot"
    BindStop = "stop"
    BindPing = "ping"
    BindCenter = "center"
    BindFollow = "follow"
    BindTakeOver = "takeover"
    BindUpgrade1 = "upgrade1"
    BindUpgrade2 = "upgrade2"
    BindUpgrade3 = "upgrade3"
    BindUpgrade4 = "upgrade4"
    BindWall = "wall"
    BindMine = "mine"
    BindWard = "ward"
    BindMute = "mute"
    BindRematch = "rematch"
    BindPan = "pan"
    BindDirector = "director"

const DefaultKeyBinds: array[BindAction, Button] = [
  # Stop lives on X: WASD steers the butcher directly now.
  # F blink: E is already grapple; Space stays free for rebinds.
  # R rot in-match; rematch keeps R on the end screen only.
  KeyQ, KeyE, KeyF, KeyR, KeyX, KeyG, KeyF1, KeyL, KeyT,
  Key1, Key2, Key3, Key4, KeyC, KeyV, KeyB, KeyM, KeyR,
  # Hold to grab-pan the camera (trackpad: no mouse button). Shares C
  # with wall: a tap still arms the palisade, a hold-and-move pans.
  KeyC,
  KeyY
]

var
  keyBinds = DefaultKeyBinds
  fileQuickcast*: bool
  fileAutocast*: bool
  fileQuickcastSet*: bool
  fileAutocastSet*: bool

proc parseOnOff(value: string): tuple[ok, enabled: bool] =
  ## Parses legacy casting options.
  case value.toLowerAscii()
  of "on", "true", "yes", "1": (true, true)
  of "off", "false", "no", "0": (true, false)
  else:
    echo "keys: expected on/off, got '", value, "'"
    (false, false)

proc bindKey*(action: BindAction): Button =
  ## The button currently bound to one action.
  keyBinds[action]

proc panSharesWall*(): bool =
  ## True when camera-grab and wall use the same button (tap vs hold).
  bindKey(BindPan) != ButtonUnknown and bindKey(BindPan) == bindKey(BindWall)

proc bindLabel*(action: BindAction): string =
  ## Short uppercase HUD label for the bound button, e.g. "Q" or
  ## "SPACE" or "MOUSE4".
  result = $keyBinds[action]
  if keyBinds[action] == ButtonUnknown:
    return "-"
  result.removePrefix("Key")
  result = result.toUpperAscii()

proc loadKeyBinds*(path: string): bool =
  ## Applies overrides from a bindings file. Returns whether the file
  ## existed; bad lines warn and change nothing.
  if not fileExists(path):
    return false
  for rawLine in lines(path):
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("#") or line.startsWith(";"):
      continue
    let split = line.find('=')
    if split < 0:
      echo "keys: ignored line without '=': ", line
      continue
    let
      actionName = line[0 ..< split].strip().toLowerAscii()
      keyName = line[split + 1 .. ^1].strip()
    if actionName == "quickcast":
      let parsed = parseOnOff(keyName)
      if parsed.ok:
        fileQuickcast = parsed.enabled
        fileQuickcastSet = true
      continue
    if actionName == "autocast":
      let parsed = parseOnOff(keyName)
      if parsed.ok:
        fileAutocast = parsed.enabled
        fileAutocastSet = true
      continue
    var action: BindAction
    try:
      action = parseEnum[BindAction](actionName)
    except ValueError:
      echo "keys: unknown action '", actionName, "'"
      continue
    try:
      keyBinds[action] = parseEnum[Button](keyName)
    except ValueError:
      echo "keys: unknown key '", keyName, "' for ", actionName
  true

when not defined(headless):
  import
    jsony, silky, vmath,
    polyworld/[inputs, menus, sounds],
    homes

  type PudgeControls = object
    bindings: array[BindAction, Button] = DefaultKeyBinds
    quickcast, autocast: bool

  const
    ControlsFile = "pudge-controls.json"
    ControlLabels: array[BindAction, string] = [
      "Meat Hook", "Grapple", "Blink", "Rot", "Stop", "Ping", "Center camera",
      "Follow butcher", "Take over butcher", "Upgrade hook damage",
      "Upgrade hook distance", "Upgrade hook speed", "Upgrade hook radius",
      "Place palisade", "Place mine", "Place ward", "Mute audio", "Rematch",
      "Drag camera", "Spectator director"
    ]
    PudgeControlProfile* = block:
      var profile: ControlProfile
      for action in InputAction:
        profile.defaults[action] = [ButtonUnknown, ButtonUnknown]
      profile.defaults[MenuInput] = [KeyEscape, KeyF9]
      profile.defaults[FullscreenInput] = [KeyF12, ButtonUnknown]
      profile.defaults[DebugInput] = [KeyF6, ButtonUnknown]
      profile.defaults[TraceInput] = [KeyF2, ButtonUnknown]
      for action in [MenuInput, FullscreenInput, DebugInput, TraceInput]:
        profile.actions.add ControlBinding(action: action, label: $action)
      profile
    ReservedKeys = {
      KeyW, KeyA, KeyS, KeyD, KeyUp, KeyDown, KeyLeft, KeyRight,
      KeyP, KeyLeftBracket, KeyF3, KeyF7, KeyF8, KeyF11,
      Key5, Key6, Key7, Key8, Key9, MouseLeft, MouseRight, MouseMiddle
    }

  var
    capturingPudge: bool
    capturePudgeAction: BindAction
    capturePudgeError: string
    launchName: string

  proc setPudgeLaunchName*(name: string) =
    ## Keeps an explicit launch name active through match and menu transitions.
    launchName = name

  proc readPudgePreferences*(): Preferences =
    ## Loads the common settings profile using Pudge's own shared shortcuts.
    result = readPreferences(PudgeAppName)
    if getConfig(PudgeAppName, "settings.json").len == 0:
      result.bindings = PudgeControlProfile.defaults
    if launchName.len > 0:
      result.name = launchName

  proc loadPudgeControls*(quickcast, autocast: var bool, keysPath = "") =
    ## Imports legacy defaults and applies the profile and explicit launch flags.
    let
      launchQuickcast = quickcast
      launchAutocast = autocast
      path = if keysPath.len > 0: keysPath else: "pudge_keys.cfg"
    keyBinds = DefaultKeyBinds
    fileQuickcastSet = false
    fileAutocastSet = false
    if loadKeyBinds(path):
      if fileQuickcastSet:
        quickcast = fileQuickcast
      if fileAutocastSet:
        autocast = fileAutocast
    elif keysPath.len > 0:
      echo "keys: no such file ", path
    let saved = getConfig(PudgeAppName, ControlsFile)
    if keysPath.len == 0 and saved.len > 0:
      try:
        let profile = saved.fromJson(PudgeControls)
        keyBinds = profile.bindings
        quickcast = profile.quickcast
        autocast = profile.autocast
      except JsonError as problem:
        echo "keys: cannot read settings: ", problem.msg
    quickcast = quickcast or launchQuickcast
    autocast = autocast or launchAutocast

  proc savePudgeControls*(quickcast, autocast: bool) =
    ## Saves the Pudge-owned fields alongside the common profile.
    let profile = PudgeControls(
      bindings: keyBinds, quickcast: quickcast, autocast: autocast
    )
    setConfig(PudgeAppName, ControlsFile, profile.toJson())

  proc pudgeBindingCapture*(): bool =
    ## Suppresses gameplay shortcuts while an individual binding is captured.
    capturingPudge

  proc usesPudgeKey(key: Button): bool =
    ## Checks whether a nonempty button belongs to a Pudge action.
    key != ButtonUnknown and (key in keyBinds or key in DefaultKeyBinds)

  proc compatiblePudgeActions(first, second: BindAction): bool =
    ## Preserves the intentional tap/hold and in-game/rematch key pairs.
    {first, second} in [{BindWall, BindPan}, {BindRot, BindRematch}]

  proc drawPudgeControls(sk: Silky, window: Window, origin: Vec2,
      quickcast, autocast: var bool) =
    ## Draws game settings and rebindable controls inside the shared frame.
    let
      wasCapturing = capturingPudge
      oldKeys = keyBinds
      oldQuickcast = quickcast
      oldAutocast = autocast
    if wasCapturing:
      for key in Button:
        if key in {ButtonUnknown, DoubleClick, TripleClick, QuadrupleClick} or
          not window.buttonPressed[key]:
            continue
        if key != KeyEscape:
          let chosen = if key == KeyBackspace: ButtonUnknown else: key
          if chosen in ReservedKeys:
              capturePudgeError = chosen.bindingLabel & " has a fixed action."
          else:
            for control in PudgeControlProfile.actions:
              if inputBindings.matches(control.action, chosen):
                capturePudgeError = chosen.bindingLabel & " is used by " &
                  control.label & "."
            if capturePudgeError.len == 0:
              if chosen != ButtonUnknown:
                for action in BindAction:
                  if action != capturePudgeAction and keyBinds[action] == chosen and
                    not compatiblePudgeActions(action, capturePudgeAction):
                      keyBinds[action] = ButtonUnknown
              keyBinds[capturePudgeAction] = chosen
        capturingPudge = false
        break
    sk.at = origin
    if not wasCapturing and not bindingCapture:
      checkBox "Quickcast", quickcast
    else:
      sk.menuLabel("Quickcast", origin)
    sk.at = origin + vec2(240, 0)
    if not wasCapturing and not bindingCapture:
      checkBox "Autocast Meat Hook", autocast
    else:
      sk.menuLabel("Autocast Meat Hook", sk.at)
    let hint =
      if wasCapturing:
        "Press a button. Esc cancels. Backspace clears."
      elif capturePudgeError.len > 0:
        capturePudgeError
      else:
        "WASD moves your butcher. Right-click issues an order."
    sk.menuLabel(hint, origin + vec2(0, 40), 660)
    for action in BindAction:
      let row = origin + vec2(0, 78 + action.ord.float32 * 38)
      sk.menuLabel(ControlLabels[action], row, 294)
      sk.at = row + vec2(300, 0)
      let label =
        if wasCapturing and action == capturePudgeAction: "Press a button..."
        else: keyBinds[action].bindingLabel
      button label, not wasCapturing and not bindingCapture:
        playSound(ClickSound)
        capturePudgeAction = action
        capturePudgeError = ""
        capturingPudge = true
    sk.at = origin + vec2(0, 92 + (high(BindAction).ord + 1).float32 * 38)
    button "Reset Pudge controls", not wasCapturing and not bindingCapture:
      playSound(ClickSound)
      keyBinds = DefaultKeyBinds
      quickcast = false
      autocast = false
      capturePudgeError = ""
    if keyBinds != oldKeys or quickcast != oldQuickcast or autocast != oldAutocast:
      savePudgeControls(quickcast, autocast)

  proc pudgeSettingsPanel*(sk: Silky, window: Window,
      preferences: var Preferences, origin: Vec2, quickcast, autocast: var bool,
      title = "Settings", height = 440.0'f): bool =
    ## Uses the common four tabs with Pudge's game-specific controls appended.
    var drewControls: bool
    let
      previousName = preferences.name
      quickcastPtr = addr quickcast
      autocastPtr = addr autocast
      extension = ControlExtension(
        capturing: pudgeBindingCapture,
        validateBinding: proc(action: InputAction, key: Button): string =
          ## Protects gameplay and fixed movement shortcuts from shared bindings.
          if key.usesPudgeKey or key in ReservedKeys:
            return key.bindingLabel & " is already used in Pudge Wars.",
        draw: proc(sk: Silky, window: Window, origin: Vec2) =
          ## Applies casting changes directly to the local controls.
          drewControls = true
          sk.drawPudgeControls(window, origin, quickcastPtr[], autocastPtr[])
      )
    result = sk.settingsPanel(
      window, preferences, PudgeAppName, origin, title, height,
      PudgeControlProfile, extension
    )
    if preferences.name != previousName:
      setPudgeLaunchName("")
    if result or not drewControls:
      capturingPudge = false
      capturePudgeError = ""
