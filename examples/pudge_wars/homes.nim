import std/[strutils, unicode]
import polyworld/rooms

const PudgeAppName* {.strdefine.} = "Pudge Wars"

proc confirmedPlayerName*(name: string, explicit = false): bool =
  ## Accepts valid names while reserving the unconfirmed default for name entry.
  name.len <= 64 and name.validName and name.validateUtf8 == -1 and
    (explicit or strutils.strip(name).toLowerAscii != "player")

proc opensMultiplayer*(room: string): bool =
  ## Routes invitations to multiplayer while retaining the ordinary home screen.
  strutils.strip(room).len > 0

when not defined(headless):
  import
    std/os,
    pixie, silky, vmath, windy,
    polyworld/[common, menus], polyworld/homes as sharedHomes

  export sharedHomes

  const Cover = staticRead("cover.webp")

  proc addPudgeHomeAssets*(builder: AtlasBuilder) =
    ## Fits the Pudge artwork and volcanic terrain into the common home layout.
    template pack(key: string, image: Image) =
      if not builder.addImage(key, image):
        raise newException(MenusError, "The UI atlas is too small for " & key)

    let
      cover = decodeImage(Cover)
      logo = newImage(600, 400)
      factor = 400'f / cover.height.float32
    logo.draw(
      cover,
      translate(vec2((600 - cover.width.float32 * factor) / 2, 0)) *
      scale(vec2(factor))
    )
    pack("home-logo", logo)

    let
      background = newImage(836, 470)
      tilePath = DataRoot / "terrain/tiles/crypt-rock-1.rgb.png"
      glow = newPaint(RadialGradientPaint)
    background.fill(rgba(26, 17, 15, 255))
    if fileExists(tilePath):
      let stone = readImage(tilePath).resize(256, 256)
      for y in [0, 256]:
        for x in [0, 256, 512, 768]:
          background.draw(stone, translate(vec2(x.float32, y.float32)))
      background.fillPath("M0 0 H836 V470 H0 Z", rgba(26, 12, 12, 146))
    glow.gradientHandlePositions = @[vec2(418, 224), vec2(836, 224), vec2(418, 530)]
    glow.gradientStops = @[
      ColorStop(color: color(0.9, 0.32, 0.08, 0.25), position: 0),
      ColorStop(color: color(0.26, 0.06, 0.03, 0.35), position: 0.55),
      ColorStop(color: color(0.035, 0.023, 0.025, 0.9), position: 1)
    ]
    background.fillPath("M0 0 H836 V470 H0 Z", glow)
    pack("home-background", background)

    let
      shade = newImage(256, 256)
      gradient = newPaint(RadialGradientPaint)
    gradient.gradientHandlePositions = @[vec2(128), vec2(256, 128), vec2(128, 256)]
    gradient.gradientStops = @[
      ColorStop(color: color(0, 0, 0, 0.7), position: 0),
      ColorStop(color: color(0, 0, 0, 0.38), position: 0.53),
      ColorStop(color: color(0, 0, 0, 0), position: 1)
    ]
    shade.fill(gradient)
    pack("home-shade", shade)

    for i in 2 ..< MenuImages.len:
      let
        face = newImage(480, 76)
        primary = i == 2
        gloss = newPaint(LinearGradientPaint)
      face.fillPath("M12 0 H468 L480 12 V64 L468 76 H12 L0 64 V12 Z",
        rgba(18, 12, 14, 255))
      face.fillPath("M13 3 H467 L477 13 V63 L467 73 H13 L3 63 V13 Z",
        if primary: rgba(247, 175, 80, 255) else: rgba(119, 73, 49, 255))
      gloss.gradientHandlePositions = @[vec2(0, 6), vec2(0, 70)]
      gloss.gradientStops =
        if primary:
          @[ColorStop(color: color(1.0, 0.77, 0.44, 1), position: 0),
            ColorStop(color: color(0.78, 0.37, 0.13, 1), position: 1)]
        else:
          @[ColorStop(color: color(0.34, 0.19, 0.15, 1), position: 0),
            ColorStop(color: color(0.15, 0.09, 0.09, 1), position: 1)]
      face.fillPath("M15 6 H465 L474 15 V61 L465 70 H15 L6 61 V15 Z", gloss)
      pack("home-" & MenuImages[i], face)

  proc drawPudgeHome*(sk: Silky, window: Window, focus: var int): HomeAction =
    ## Uses the shared keyboard and pointer behavior with the Pudge title art.
    sharedHomes.drawHome(sk, window, focus, compact = true)

  proc effectivePreferences*(stored: Preferences, inviteServer,
      configuredServer: string): Preferences =
    ## Gives an invitation address precedence over the launch and saved values.
    result = stored
    if inviteServer.len > 0:
      result.server = inviteServer
    elif configuredServer.len > 0:
      result.server = configuredServer
