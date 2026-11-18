import
  std/[strutils, unicode, uri],
  polyworld/rooms,
  content, homes

proc defaultRoomName*(name: string): string =
  ## Gives named players an editable starting room title.
  if name.confirmedPlayerName: name & "'s game" else: ""

proc roomNameValid*(name: string): bool =
  ## Validates names before sending a create or configure request.
  name.len <= 96 and name.validName and name.validateUtf8 == -1

proc displaySeat*(seat, teamSize: int): int =
  ## Maps the relay's contiguous roster to the shared five-row bank cards.
  seat div teamSize * MaxTeamSize + seat mod teamSize

proc lobbySeat*(seat, teamSize: int): int =
  ## Converts a visible bank card into its index in the current room revision.
  if seat notin 0 ..< MaxPudgeCount or seat mod MaxTeamSize >= teamSize:
    return -1
  seat div MaxTeamSize * teamSize + seat mod MaxTeamSize

proc opposingBanks*(seats: openArray[Seat], teamSize: int): bool =
  ## Requires at least one controller for each bank before starting.
  var occupied: array[2, bool]
  for i, seat in seats:
    if i < teamSize * 2 and seat.owner != 0:
      occupied[i div teamSize] = true
  occupied[0] and occupied[1]

proc parseInvite*(input: string): tuple[server, room: string] =
  ## Accepts a room code or the same invite links shared by the room UI.
  let value = strutils.strip(input)
  if value.len == 0:
    reject("Enter an invite link or room code.")
  if '?' notin value:
    result.room = value
  else:
    for key, argument in decodeQuery(parseUri(value).query):
      case key
      of "server": result.server = argument
      of "room": result.room = strutils.strip(argument)
      else: discard
  if result.room.len > 64 or not result.room.validName or
    result.room.validateUtf8 != -1:
    reject("The invite must contain a valid room code.")

when not defined(headless):
  import
    std/random,
    bumpy, chroma, silky, vmath, windy,
    polyworld/[connections, roomclients],
    polyworld/lobbies as sharedLobbies,
    maps, presets

  export sharedLobbies

  type
    BrowserAction* = enum
      BrowseRooms, ConnectRelay, CreateLobby, JoinLobby, CloseBrowser
    RoomBrowser* = object
      server*, roomName*, invite*: string
      public*: bool = true
    BrowserChoice* = object
      action*: BrowserAction
      room*: string

  proc drawRoomBrowser*(sk: Silky, window: Window, layout: LobbyLayout,
      ui: var LobbyUi, browser: var RoomBrowser,
      connection: Connection): BrowserChoice =
    ## Draws the shared room browser layout with invite and visibility controls.
    let
      connected = connection != nil and connection.client.welcomed
      p = layout.origin + vec2(32, 144)
      totalWidth = if layout.compact: 936.0'f else: 1450.0'f
    sk.lobbyPanel(p, vec2(totalWidth, 74))
    sk.lobbyLabel("Server", p + vec2(20, 16), 90, "LobbyBold")
    sk.lobbyInput(window, "server", browser.server,
      p + vec2(112, 15), totalWidth - 470)
    if sk.lobbyButton(if connected: "Reconnect" else: "Connect",
      p + vec2(totalWidth - 340, 15), 160):
        result.action = ConnectRelay
    sk.lobbyIcon("status", p + vec2(totalWidth - 156, 23), 24,
      if connected: LobbyGreen else: LobbyMuted)
    sk.lobbyLabel(if connected: "Connected" else: "Offline",
      p + vec2(totalWidth - 122, 16), 116)

    sk.lobbyPanel(layout.left, vec2(layout.leftWidth, layout.panelHeight))
    let list = layout.left + vec2(22)
    sk.lobbyIcon("units", list + vec2(0, 8), 38)
    sk.lobbyLabel("PUBLIC ROOMS", list + vec2(50, 0), 500, "LobbyHeading")
    sk.lobbyLabel("Rooms for this game version", list + vec2(50, 38),
      500, tint = LobbyMuted)
    if sk.lobbyButton("Refresh", list + vec2(layout.leftWidth - 204, 6),
      160, "loop", connected):
        connection.client.send(RoomMessage(kind: ListRooms))
    sk.lobbyIcon("search", list + vec2(4, 94))
    sk.lobbyInput(window, "roomSearch", ui.search,
      list + vec2(44, 84), layout.leftWidth - 88)
    sk.lobbyLabel("ROOM", list + vec2(0, 136), 360, tint = LobbyMuted)
    sk.lobbyLabel("PLAYERS", list + vec2(390, 136), 130, tint = LobbyMuted)
    sk.lobbyLabel("STATUS", list + vec2(540, 136), 130, tint = LobbyMuted)
    var listings: seq[RoomListing]
    if connected:
      let search = ui.search.toLowerAscii()
      for room in connection.client.listings:
        if search in room.name.toLowerAscii():
          listings.add room
    let
      rowsAt = list + vec2(0, 184)
      rowsSize = vec2(layout.leftWidth - 44, layout.panelHeight - 268)
      contentSize = vec2(rowsSize.x, listings.len.float32 * 68)
    if ui.roomScroll == nil:
      ui.roomScroll = FrameState()
    ui.roomListOverflow = contentSize.y > rowsSize.y
    sk.frameScrollbars(window, ui.roomScroll, rect(rowsAt, rowsSize),
      contentSize, vec2(1))
    sk.pushClipRect(rect(rowsAt, rowsSize - vec2(14, 0)))
    for row, room in listings:
      let
        point = rowsAt - ui.roomScroll.scrollPos + vec2(0, row.float32 * 68)
        full = room.occupied == room.seats
        watching = room.phase != rooms.Lobby or full
      sk.lobbyPanel(point, vec2(rowsSize.x - 16, 60), true)
      sk.lobbyLabel(room.name, point + vec2(12, 10), 365, "LobbyBold")
      sk.lobbyLabel($room.occupied & " / " & $room.seats,
        point + vec2(390, 10), 130)
      sk.lobbyIcon("status", point + vec2(540, 20), 20,
        if watching: LobbyMuted else: LobbyGreen)
      sk.lobbyLabel(if room.phase != rooms.Lobby: $room.phase
        elif full: "Full" else: "Open", point + vec2(570, 10), 120)
      if sk.lobbyButton(if watching: "Watch" else: "Join",
        point + vec2(rowsSize.x - 156, 8), 128, "arrow_right"):
          result = BrowserChoice(action: JoinLobby, room: room.id)
    sk.popClipRect()
    if listings.len == 0:
      sk.lobbyLabel(if not connected: connection.status()
        elif ui.search.len == 0: "No public rooms"
        else: "No rooms match your search", rowsAt, rowsSize.x, tint = LobbyMuted)

    sk.lobbyPanel(layout.right, vec2(layout.rightWidth, layout.panelHeight))
    let
      create = layout.right + vec2(22)
      width = layout.rightWidth - 44
    sk.lobbyIcon("cross", create + vec2(0, 8), 32)
    sk.lobbyLabel("CREATE ROOM", create + vec2(44, 0), width - 44,
      "LobbyHeading")
    sk.lobbyLabel("Room name", create + vec2(0, 52), width)
    sk.lobbyInput(window, "roomName", browser.roomName,
      create + vec2(0, 96), width)
    sk.lobbyLabel("Visibility", create + vec2(0, 146), width)
    if sk.lobbyButton("Public", create + vec2(0, 190), width / 2 - 6,
      "globe", selected = browser.public):
        browser.public = true
    if sk.lobbyButton("Private", create + vec2(width / 2 + 6, 190),
      width / 2 - 6, "lock", selected = not browser.public):
        browser.public = false
    sk.lobbyLabel(if browser.public: "Listed in public rooms."
      else: "Only people with an invite can join.",
      create + vec2(0, 238), width, tint = LobbyMuted)
    if sk.lobbyButton("Create Room", create + vec2(0, 288), width,
      "cross", connected and browser.roomName.roomNameValid):
        result.action = CreateLobby
    sk.lobbyIcon("link", create + vec2(0, 368))
    sk.lobbyLabel("JOIN BY INVITE", create + vec2(44, 360), width - 44,
      "LobbyHeading")
    sk.lobbyLabel("Invite link or room code", create + vec2(0, 410), width)
    sk.lobbyInput(window, "inviteRoom", browser.invite,
      create + vec2(0, 456), width)
    if sk.lobbyButton("Join Room", create + vec2(0, layout.panelHeight - 72),
      width, "arrow_right", strutils.strip(browser.invite).len > 0):
        result.action = JoinLobby
    if sk.lobbyButton("Back", layout.footer, 190, "arrow_left") or
      window.buttonPressed[KeyEscape]:
        result.action = CloseBrowser

  proc drawPudgeRoster*(sk: Silky, layout: LobbyLayout) =
    ## Draws the opposing bank headings for the standard seat grid.
    sk.lobbyPanel(layout.left, vec2(layout.leftWidth, layout.panelHeight))
    sk.lobbyIcon("tower", layout.left + vec2(24, 24), 36, LobbyRed)
    sk.lobbyLabel("WEST BANK", layout.left + vec2(70, 22), 280,
      "LobbyHeading", LobbyRed)
    let east = layout.left + vec2(layout.leftWidth / 2, 0)
    sk.lobbyIcon("tower", east + vec2(24, 24), 36, LobbyBlue)
    sk.lobbyLabel("EAST BANK", east + vec2(70, 22), 280,
      "LobbyHeading", LobbyBlue)

  proc removeBotDialog*(sk: Silky, window: Window, name: string): SlotChoice =
    ## Confirms the host's request to clear another participant's bot.
    let
      view = window.size.vec2 / sk.uiScale
      size = vec2(520, 152)
      at = (view - size) * 0.5'f
    sk.pushLayer(PopupsLayer)
    sk.drawRect(vec2(0), view, rgbx(0, 0, 0, 180))
    discard sk.interact(rect(vec2(0), view), true)
    sk.lobbyPanel(at, size)
    sk.lobbyLabel("Remove " & name & "?", at + vec2(24, 20), 472,
      "LobbyHeading")
    if sk.lobbyButton("Remove bot", at + vec2(24, 84), 226, "minus"):
      result = SlotChoice(chosen: true, clear: true)
    elif sk.lobbyButton("Cancel", at + vec2(270, 84), 226, "arrow_left") or
      window.buttonPressed[KeyEscape]:
        result = SlotChoice(chosen: true)
    sk.popLayer()

  proc drawArenaPreview(sk: Silky, config: MatchConfig, at, size: Vec2) =
    ## Draws the playable bank edges, fountain, and actual seeded spawn pads.
    sk.lobbyPanel(at, size, true)
    let
      origin = at + vec2(12)
      dimensions = size - vec2(24)
      tile = vec2(dimensions.x / PlayableWidthTiles.float32,
        dimensions.y / PlayableDepthTiles.float32)
      west = rgbx(95, 49, 39, 255)
      east = rgbx(43, 54, 74, 255)
    sk.drawRect(origin, dimensions, rgbx(59, 27, 19, 255))
    for z in PlayZMin .. PlayZMax:
      let
        y = (z - PlayZMin).float32 * tile.y
        westEdge = (playWestMaxAt(z) - PlayWestMin + 1).float32 * tile.x
        eastEdge = (playEastMinAt(z) - PlayWestMin).float32 * tile.x
      sk.drawRect(origin + vec2(0, y), vec2(westEdge, tile.y + 0.1'f), west)
      sk.drawRect(origin + vec2(eastEdge, y),
        vec2(dimensions.x - eastEdge, tile.y + 0.1'f), east)
      let middle = (RiverCenterX - PlayWestMin).float32 * tile.x
      sk.drawRect(origin + vec2(middle - tile.x, y),
        vec2(tile.x * 2, tile.y + 0.1'f), rgbx(123, 57, 24, 255))
    proc padAt(x, z: int): Vec2 =
      ## Maps an arena tile coordinate to the minimap overlay.
      origin + vec2((x - PlayWestMin).float32 * tile.x,
        (z - PlayZMin).float32 * tile.y)
    sk.drawRect(padAt(IslandCenterX, IslandCenterZ) - vec2(11, 7),
      vec2(22, 14), rgbx(198, 157, 96, 255))
    let pads = spawnLayoutFromSeed(config.seed, config.teamSize)
    for i in 0 ..< config.teamSize:
      sk.drawRect(padAt(pads.west[i].x, pads.west[i].z) - vec2(4), vec2(8), LobbyRed)
      sk.drawRect(padAt(pads.east[i].x, pads.east[i].z) - vec2(4), vec2(8), LobbyBlue)

  proc drawMatchSettings*(sk: Silky, window: Window, layout: LobbyLayout,
      config: var MatchConfig, rng: var Rand, enabled: bool,
      name: ptr string = nil, public: ptr bool = nil) =
    ## Shows the fixed Pudge arena and edits the game-owned lobby settings.
    sk.lobbyPanel(layout.right, vec2(layout.rightWidth, layout.panelHeight))
    let
      at = layout.right + vec2(22)
      width = layout.rightWidth - 44
    sk.lobbyIcon("settings", at + vec2(0, 8), 34)
    sk.lobbyLabel("MATCH SETTINGS", at + vec2(44, 0), width - 44,
      "LobbyHeading")
    sk.lobbyLabel("Fire Pit", at + vec2(0, 46), width, "LobbyBold")
    sk.drawArenaPreview(config, at + vec2(0, 88), vec2(width, 168))
    var fields = at + vec2(0, 278)
    if name != nil:
      sk.lobbyLabel("Room name", fields, 190)
      if enabled:
        sk.lobbyInput(window, "matchName", name[], fields + vec2(196, 0),
          width - 196)
      else:
        sk.lobbyLabel(name[], fields + vec2(196, 0), width - 196, tint = LobbyMuted)
      fields.y += 52
    sk.lobbyNumber("Seats per bank", config.teamSize, fields, width,
      1, MaxTeamSize, 1, enabled)
    sk.lobbyNumber("Kill goal", config.killGoal, fields + vec2(0, 48), width,
      1'i32, 999'i32, 1'i32, enabled)
    var seconds = max(1'i32, config.maxTicks div TickRate)
    let previousSeconds = seconds
    sk.lobbyNumber("Time limit (s)", seconds, fields + vec2(0, 96), width,
      1'i32, MaxMatchTicks div TickRate, 60'i32, enabled)
    if seconds != previousSeconds:
      config.maxTicks = seconds * TickRate
    var runeSeconds = config.runePeriod div TickRate
    let previousRunes = runeSeconds
    sk.lobbyNumber("Rune interval (s)", runeSeconds, fields + vec2(0, 144),
      width, 0'i32, 120'i32, 5'i32, enabled)
    if runeSeconds != previousRunes:
      config.runePeriod = runeSeconds * TickRate
    let difficultyAt = fields + vec2(0, 192)
    sk.lobbyLabel("Bot difficulty", difficultyAt, 180)
    let buttonWidth = (width - 212) / 3
    for difficulty in BotDifficulty:
      var sample = config
      sample.setDifficulty(difficulty)
      let chosen = sample.botEvery == config.botEvery and
        sample.botAimNoise == config.botAimNoise
      if sk.lobbyButton($difficulty, difficultyAt +
        vec2(196 + (buttonWidth + 8) * difficulty.ord.float32, 0), buttonWidth,
        enabled = enabled, selected = chosen, height = 40):
          config.setDifficulty(difficulty)
    let seedAt = fields + vec2(0, 240)
    sk.lobbyNumber("Map seed", config.seed, seedAt, width - 54,
      int32.low, int32.high, 1'i32, enabled)
    if sk.lobbyButton("", seedAt + vec2(width - 44, 0), 44,
      "shuffle", enabled, height = 40):
        config.seed = rng.rand(1 .. int32.high.int).int32
    if public != nil:
      let visibility = fields + vec2(0, 288)
      sk.lobbyLabel("Visibility", visibility, 190)
      let part = (width - 204) * 0.5'f
      if sk.lobbyButton("Public", visibility + vec2(196, 0), part, "",
        enabled, selected = public[], height = 40):
          public[] = true
      if sk.lobbyButton("Private", visibility + vec2(204 + part, 0), part, "",
        enabled, selected = not public[], height = 40):
          public[] = false
