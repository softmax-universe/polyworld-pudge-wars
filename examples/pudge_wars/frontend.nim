import
  std/[random, uri],
  chroma, silky, vmath, windy,
  polyworld/[chrome, connections, displays, inputs, menus, pointers, sounds,
    viewers],
  content, game, graphics, homes, keybinds, lobbies, multiplayer, sim

type
  Setup = object
    config: MatchConfig
    policies: array[MaxPudgeCount, LocalPolicy]
    human: int = -1
  RoomSettings = object
    config: MatchConfig
    name: string
    public: bool
  RoomLobby = object
    room, payload: string
    accepted, draft, waiting: RoomSettings
    applying, claiming, joined, leaving: bool
    policies: array[MaxPudgeCount, LocalPolicy]
    prepared: NetworkMatch

when defined(emscripten):
  proc presentationReady() {.
    importc: "pwFrontendPresentationReady", nodecl.}
  {.emit: """
  #include <emscripten.h>
  EM_JS(void, pwFrontendPresentationReady, (), {
    window.pwPresentationReady?.();
  });
  """.}

proc seats(setup: Setup, name: string): seq[Seat] =
  ## Preserves the same West and East slot IDs offline and online.
  result.setLen(MaxPudgeCount)
  for i in 0 ..< result.len:
    if not setup.config.seatEnabled(i):
      continue
    if i == setup.human:
      result[i] = Seat(owner: 1, kind: HumanSeat, name: name)
    elif setup.policies[i].bytes.len > 0:
      result[i] = Seat(owner: 1, kind: BotSeat, name: setup.policies[i].name)

proc sources(policies: array[MaxPudgeCount, LocalPolicy]): array[MaxPudgeCount, string] =
  ## Keeps policy source private and indexed by stable seat ID.
  for i, policy in policies:
    result[i] = policy.bytes

proc discardPreparation(lobby: var RoomLobby) =
  ## Frees local bot runtimes belonging to an abandoned preparation.
  if lobby.prepared != nil:
    lobby.prepared.close()
    lobby.prepared = nil

proc clearRoom(lobby: var RoomLobby) =
  ## Resets local state on leaving, while keeping application settings.
  lobby.discardPreparation()
  lobby = RoomLobby()

proc observe(lobby: var RoomLobby, client: RoomClient) =
  ## Accepts authoritative room settings without clobbering a local draft.
  let snapshot = client.snapshot
  if lobby.room != snapshot.room:
    lobby.clearRoom()
    lobby.room = snapshot.room
  if snapshot.room.len == 0:
    return
  let config =
    if lobby.payload == snapshot.payload and lobby.accepted.config.teamSize > 0:
      lobby.accepted.config
    else:
      snapshot.payload.parseConfig()
  if snapshot.phase == rooms.Lobby and not client.began and
    snapshot.seats.len != MaxPudgeCount:
      reject("The room must provide five stable seats per bank")
  lobby.payload = snapshot.payload
  let settings = RoomSettings(
    config: config, name: snapshot.name,
    public: if snapshot.phase == rooms.Lobby: snapshot.flag
      else: lobby.accepted.public
  )
  if lobby.accepted != settings:
    if not lobby.applying or lobby.waiting == settings:
      lobby.draft = settings
    lobby.accepted = settings
  if lobby.applying and lobby.waiting == settings:
    lobby.applying = false
  if not client.welcomed:
    lobby.claiming = false
    lobby.applying = false
    lobby.leaving = false
    lobby.discardPreparation()
  elif not client.began and lobby.prepared != nil and
    lobby.prepared.revision != snapshot.revision:
      lobby.discardPreparation()

proc claimArrival(lobby: var RoomLobby, client: RoomClient) =
  ## Claims one open human seat on arrival and preserves later seat choices.
  if lobby.joined or lobby.leaving or not client.welcomed:
    return
  let snapshot = client.snapshot
  if client.began or snapshot.phase != rooms.Lobby:
    lobby.joined = true
    return
  for seat in snapshot.seats:
    if seat.owner == client.participant:
      lobby.joined = true
      return
  if lobby.claiming:
    return
  for i, seat in snapshot.seats:
    if seat.owner == 0 and lobby.accepted.config.seatEnabled(i):
      client.claimHuman(i)
      lobby.claiming = true
      return
  lobby.joined = true

proc runDirectMatches*(present: proc(): bool) =
  ## Runs the explicit launch setup again whenever its presenter requests rematch.
  let launchRecording = options.recordPath
  defer:
    options.recordPath = launchRecording
  while true:
    options.recordPath = launchRecording
    defer:
      releaseGame()
    defer:
      if run != nil:
        closeDuelLogging()
    initializeGame()
    if present() or run.replayMode:
      return

proc runFrontend*() =
  ## Runs the home, setup, settings and match flows on one window.
  let
    queryName = inviteParameter("name")
    name =
      if options.playerName.confirmedPlayerName: options.playerName
      elif queryName.confirmedPlayerName: queryName
      else: ""
  setPudgeLaunchName(name)
  initializeGraphics()
  defer:
    closeGraphics()
  if options.replayPath.len > 0 or directPlay or defined(takeScreenshot):
    runDirectMatches(proc(): bool =
      ## Stops on a home request or window closure.
      runGraphics() or window.closeRequested
    )
    return

  let queryServer = inviteParameter("server")
  var
    preferences = Preferences(name: name, bindings: PudgeControlProfile.defaults)
    error: string
    page = HomeMenu
    focus: int
    ui = LobbyUi()
    browser = RoomBrowser()
    local = Setup(config: defaultConfig(), human: 0)
    lobby = RoomLobby()
    rng = initRand()
    connection: Connection
    pendingRoom: string
    connectRequested, launchLocal: bool
    playerDraft: string
    editPlayer = false
  when defined(emscripten):
    var reportedFrame: bool
  proc reloadPreferences() =
    ## Preserves the live application settings if reading the profile fails.
    try:
      let previous = preferences
      preferences = effectivePreferences(
        readPudgePreferences(), queryServer, serverAddress
      )
      if browser.server == previous.server:
        browser.server = preferences.server
      if browser.roomName == defaultRoomName(previous.name):
        browser.roomName = defaultRoomName(preferences.name)
    except MenusError, IOError, OSError:
      error = getCurrentExceptionMsg()
  reloadPreferences()
  preferences = effectivePreferences(preferences, queryServer, serverAddress)
  browser.server = preferences.server
  browser.roomName = defaultRoomName(preferences.name)
  browser.invite = inviteParameter("room")
  if browser.invite.len == 0:
    browser.invite = roomCode
  if browser.invite.opensMultiplayer:
    page = MultiplayerMenu
    try:
      let invite = parseInvite(browser.invite)
      pendingRoom = invite.room
      if invite.server.len > 0:
        browser.server = invite.server
      connectRequested = true
    except CatchableError as problem:
      error = problem.msg

  var bots: seq[LocalPolicy]
  for (name, bytes) in BotPolicies:
    bots.add LocalPolicy(name: name, bytes: bytes)
  ui.selectedBot = bots[0].name
  local.config.seed = options.seed
  local.config.teamSize = if options.duel: 1 else: int(options.teamSize)
  local.config.maxTicks = min(options.maximumTicks, MaxMatchTicks)
  local.config.killGoal = options.killGoal
  local.config.botEvery = options.botEvery
  local.config.botAimNoise = min(options.botAimNoise, 128'i32)
  local.config.runePeriod = optionRunePeriod()
  for i in 0 ..< MaxPudgeCount:
    if i != local.human and local.config.seatEnabled(i):
      local.policies[i] = bots[0]

  while not window.closeRequested:
    when not defined(emscripten):
      window.updateWindowSettings()
    if connectRequested and preferences.name.confirmedPlayerName and
      not editPlayer:
        connectRequested = false
        try:
          let address = serverUrl(browser.server)
          if connection != nil and connection.address == address:
            connection.reconnectAfter(0)
          else:
            connection.close()
            lobby.clearRoom()
            connection = connect(address, preferences.name, identity())
          preferences.server = address
          browser.server = address
          preferences.savePreferences(PudgeAppName)
          error = ""
        except CatchableError as problem:
          error = problem.msg

    if connection != nil:
      connection.pump()
      let client = connection.client
      if client.error.len > 0:
        error = client.error
        client.error = ""
        lobby.applying = false
        lobby.leaving = false
        lobby.discardPreparation()
        if lobby.claiming:
          lobby.claiming = false
      try:
        lobby.observe(client)
        if client.snapshot.room.len == 0:
          if page == LobbyMenu:
            page = MultiplayerMenu
            ui.scroll = 0
            ui.selectedSeat = -1
          if client.welcomed and pendingRoom.len > 0:
            client.send(RoomMessage(kind: JoinRoom, room: pendingRoom))
            pendingRoom = ""
        else:
          if page != LobbyMenu:
            ui.scroll = 0
            ui.selectedSeat = -1
            error = ""
          page = LobbyMenu
          lobby.claimArrival(client)
          if client.events.len > 0 and not lobby.leaving:
            let event = client.events[0]
            client.events.delete(0)
            if not client.began or event.match != client.match:
              continue
            try:
              if lobby.prepared == nil or
                lobby.prepared.revision != event.revision:
                  lobby.discardPreparation()
                  lobby.prepared = prepareNetworkMatch(
                    client, lobby.policies.sources()
                  )
              let match = lobby.prepared
              lobby.prepared = nil
              defer:
                match.close()
              match.start(event)
              connection.pump()
              window.onFrame = nil
              installGame(match.game, match.humanPudgeIndex(), networked = true)
              let home = runGraphics(match, connection)
              releaseGame()
              if home:
                connection.close()
                connection = nil
                lobby.clearRoom()
                page = HomeMenu
                error = ""
              ui.selectedSeat = -1
              reloadPreferences()
              continue
            except CatchableError as problem:
              error = problem.msg
              if run != nil:
                releaseGame()
              lobby.discardPreparation()
              if client.began and client.match == event.match:
                client.send(RoomMessage(
                  kind: AbortMatch, match: event.match, detail: error
                ))
      except CatchableError as problem:
        error = problem.msg

    launchLocal = false
    window.onButtonPress = proc(button: Button) =
      ## Applies menu zoom and fullscreen shortcuts to the shared window.
      window.captureCursorConfinement(button)
      if not editPlayer and not pudgeBindingCapture():
        discard window.scaleKey(
          button, preferences, sk.uiScale, PudgeAppName
        )
        if FullscreenInput.matches(button):
          when defined(emscripten):
            window.setFullscreen(not window.isFullscreen)
            preferences.fullscreen = window.isFullscreen
          else:
            preferences.windowMode =
              if window.windowMode == Windowed: Fullscreen else: Windowed
            window.configureWindow(
              preferences.windowMode, preferences.resolution
            )
          preferences.savePreferences(PudgeAppName)
    window.onFrame = proc() =
      ## Draws one home, room, name, or settings frame.
      beginPudgeFrame()
      updateSounds()
      window.updateCursorConfinement(preferences.edgeScrolling)
      let needsName = not preferences.name.confirmedPlayerName
      try:
        if editPlayer or (page == MultiplayerMenu and needsName):
          sk.textStyle = "Default"
          discard sk.beginSettings(window)
          sk.drawHomeBackground(window)
          let
            view = window.size.vec2 / sk.uiScale
            at = (view - vec2(620, 260)) * 0.5'f
            valid = playerDraft.confirmedPlayerName
          sk.drawRect(vec2(0), view, rgbx(0, 0, 0, 110))
          sk.lobbyPanel(at, vec2(620, 260))
          sk.drawLabel(if needsName: "Enter your player name"
            else: "Change your player name",
            at + vec2(24, 20), vec2(572, 40),
            sk.theme.defaultTextColor, "H1")
          sk.menuInput(window, "newPlayerName", playerDraft,
            at + vec2(24, 80), 572, 44)
          if playerDraft.len > 0 and not valid:
            sk.lobbyLabel("Choose a name other than Player, up to 64 bytes.",
              at + vec2(24, 128), 572, tint = LobbyMuted)
          if sk.lobbyButton("Cancel", at + vec2(24, 188), 180) or
            window.buttonPressed[KeyEscape]:
              if needsName and page == MultiplayerMenu:
                page = HomeMenu
                connectRequested = false
                pendingRoom = ""
              editPlayer = false
              playerDraft = ""
          elif sk.lobbyButton(if needsName: "Continue" else: "Save",
            at + vec2(396, 188), 200, enabled = valid) or
            (valid and window.buttonPressed[KeyEnter]):
              if browser.roomName == defaultRoomName(preferences.name):
                browser.roomName = defaultRoomName(playerDraft)
              preferences.name = playerDraft
              preferences.savePreferences(PudgeAppName)
              setPudgeLaunchName("")
              editPlayer = false
              if connection != nil and connection.client.name != playerDraft:
                connection.client.name = playerDraft
                connection.reconnectAfter(0)
        else:
          case page
          of HomeMenu:
            case sk.drawPudgeHome(window, focus)
            of StayHome: discard
            of PlaySingle:
              page = SingleMenu
              ui.scroll = 0
            of PlayMultiplayer:
              page = MultiplayerMenu
              ui.scroll = 0
              connectRequested = browser.server.strip.len > 0
            of OpenSettings: page = SettingsMenu
            of ExitGame:
              when not defined(emscripten):
                window.closeRequested = true
          of SettingsMenu:
            sk.textStyle = "Default"
            let
              at = sk.beginLobbySettings(window)
              height = max(440'f, window.size.y.float32 / sk.uiScale - at.y - 50)
              suggestedRoom = defaultRoomName(preferences.name)
            if sk.pudgeSettingsPanel(window, preferences, at,
              options.quickcast, options.autocast, "", height):
                page = HomeMenu
                browser.server = preferences.server
            if browser.roomName == suggestedRoom:
              browser.roomName = defaultRoomName(preferences.name)
          of MultiplayerMenu:
            let layout = sk.beginLobby(window, ui, "MULTIPLAYER", true)
            let choice = sk.drawRoomBrowser(window, layout, ui, browser, connection)
            case choice.action
            of BrowseRooms: discard
            of ConnectRelay: connectRequested = true
            of CreateLobby:
              let config = defaultConfig()
              connection.client.send(RoomMessage(
                kind: CreateRoom, name: browser.roomName, flag: browser.public,
                number: uint32(MaxPudgeCount), tickRate: uint32(NetworkTickRate),
                payload: config.encodeConfig()
              ))
              error = ""
            of JoinLobby:
              let invite = parseInvite(
                if choice.room.len > 0: choice.room else: browser.invite
              )
              let address = serverUrl(
                if invite.server.len > 0: invite.server else: browser.server
              )
              browser.server = address
              pendingRoom = invite.room
              connectRequested = connection == nil or
                address != connection.address
              error = ""
            of CloseBrowser:
              connection.close()
              connection = nil
              pendingRoom = ""
              connectRequested = false
              error = ""
              page = HomeMenu
          of SingleMenu, LobbyMenu:
            let
              online = page == LobbyMenu
              client = if online: connection.client else: nil
              snapshot = if online: client.snapshot else: RoomMessage()
              config = if online: lobby.accepted.config else: local.config
              shownSeats = if online: snapshot.seats
                else: local.seats(if needsName: "Player" else: preferences.name)
              editable = not online or
                (client.welcomed and not client.began and
                  snapshot.phase == rooms.Lobby and not lobby.leaving and
                  not lobby.applying and lobby.prepared == nil)
              owner = not online or snapshot.participant == client.participant
              modal = ui.selectedSeat >= 0
              layout = sk.beginLobby(window, ui, "BATTLE SETUP")
            sk.drawPudgeRoster(layout)
            var
              emptyCount, ownCount: int
              ready: bool
            if online:
              for participant in snapshot.participants:
                if participant.id == client.participant:
                  ready = participant.ready
            for i in 0 ..< min(shownSeats.len, MaxPudgeCount):
              let
                seat = shownSeats[i]
                enabled = config.seatEnabled(i)
                empty = seat.owner == 0
                mine = not online or seat.owner == client.participant
                human = not empty and seat.kind == HumanSeat
                removable = online and owner and not empty and
                  (not human or not enabled)
              if not enabled and empty:
                continue
              var
                name = if empty: "Add player" else: seat.name
                controller = if empty: "Empty slot"
                  elif human: "Human" else: "Bot"
              if empty:
                inc emptyCount
              elif online:
                if mine:
                  inc ownCount
                for participant in snapshot.participants:
                  if participant.id == seat.owner:
                    if human:
                      name = participant.name
                    controller = participant.name &
                      (if not participant.connected: " / Reconnecting"
                       elif participant.ready: " / Ready" else: " / Not ready")
              if sk.seatButton(layout, i, name, controller, human, empty,
                editable and ((enabled and (mine or empty)) or removable) and
                  not modal):
                  ui.selectedSeat = i
            if owner:
              let fill = layout.left + vec2(22, layout.panelHeight - 154)
              let width = layout.leftWidth - 44
              sk.lobbyLabel("Fill empty slots", fill, 210, "LobbyBold")
              var names: seq[string]
              for bot in bots:
                names.add bot.name
              sk.lobbyBotSelect(window, ui.selectedBot, names, ui.fillBotMenu,
                fill + vec2(216, 0), 214, editable and not modal)
              if sk.lobbyButton("Fill " & $emptyCount & " slots",
                fill + vec2(444, 0), width - 444, "cross",
                editable and emptyCount > 0 and not modal):
                  for bot in bots:
                    if bot.name != ui.selectedBot:
                      continue
                    for i, seat in shownSeats:
                      if seat.owner != 0 or not config.seatEnabled(i):
                        continue
                      if online:
                        client.send(RoomMessage(
                          kind: ClaimSeat, seat: uint32(i), name: bot.name,
                          seatKind: BotSeat
                        ))
                        lobby.policies[i] = bot
                      else:
                        local.policies[i] = bot
            if online:
              sk.drawMatchSettings(window, layout, lobby.draft.config, rng,
                owner and editable and not modal,
                addr lobby.draft.name, addr lobby.draft.public)
              let
                excluded = lobby.draft.config.excludedSeat(shownSeats)
                roomInfo =
                  if owner and excluded >= 0:
                    "Clear player " & $(excluded + 1) & " or increase the bank size."
                  elif lobby.prepared != nil: "Starting game..."
                  elif not config.opposingBanks(shownSeats):
                    "Place at least one butcher on each bank."
                  else: snapshot.name
              sk.lobbyLabel(roomInfo,
                layout.left + vec2(22, layout.panelHeight - 72),
                layout.leftWidth - 44, tint = LobbyMuted)
              if sk.lobbyButton("Copy invite", layout.footer + vec2(204, 0),
                200, "link", not modal):
                  copyInvite(inviteBase() & "?server=" & encodeUrl(connection.address) &
                    "&room=" & encodeUrl(snapshot.room))
              if sk.lobbyButton(if ready: "Ready" else: "Not ready",
                layout.footer + vec2(420, 0), 190, "status",
                editable and ownCount > 0 and not modal,
                iconTint = readinessColor(ready)):
                  client.send(RoomMessage(kind: ReadyStatus, flag: not ready))
              if owner and lobby.draft != lobby.accepted:
                if sk.lobbyButton("Apply Settings", layout.primary, 250, "settings",
                  editable and not modal and excluded < 0 and
                    lobby.draft.name.roomNameValid):
                    let payload = lobby.draft.config.encodeConfig()
                    client.send(RoomMessage(
                      kind: ConfigureRoom,
                      payload: payload, name: lobby.draft.name,
                      number: uint32(MaxPudgeCount),
                      tickRate: uint32(NetworkTickRate), flag: lobby.draft.public
                    ))
                    lobby.waiting = lobby.draft
                    lobby.applying = true
              elif owner and sk.lobbyButton("Start Game", layout.primary,
                250, "arrow_right", editable and not modal and
                  excluded < 0 and config.opposingBanks(shownSeats), tint = LobbyGreen):
                  let match = prepareNetworkMatch(client, lobby.policies.sources())
                  try:
                    client.send(match.startRequest())
                    lobby.prepared = match
                    error = ""
                  except CatchableError:
                    match.close()
                    raise
              let reopen = owner and snapshot.phase in {Ended, Desynced}
              if sk.lobbyButton(if reopen: "Return to lobby" else: "Leave room",
                layout.footer, 190, "arrow_left",
                client.welcomed and not lobby.leaving and not modal):
                  client.send(RoomMessage(
                    kind: if reopen: ReturnLobby else: LeaveRoom
                  ))
                  lobby.leaving = not reopen
                  error = ""
            else:
              sk.drawMatchSettings(window, layout, local.config, rng, not modal)
              for bank in 0 .. 1:
                for space in local.config.teamSize ..< config.teamSize:
                  local.policies[bank * MaxTeamSize + space] = LocalPolicy()
              if not local.config.seatEnabled(local.human):
                local.human = -1
              if sk.lobbyButton("Back", layout.footer, 190, "arrow_left",
                not modal) or (not modal and window.buttonPressed[KeyEscape]):
                  page = HomeMenu
              if sk.lobbyButton("Start Game", layout.primary, 250, "arrow_right",
                not modal and local.config.opposingBanks(local.seats("Player")),
                tint = LobbyGreen):
                  launchLocal = true
              sk.lobbyLabel(if local.human < 0: "Spectating bots"
                else: "Playing as " & (if needsName: "Player" else: preferences.name),
                layout.left + vec2(22, layout.panelHeight - 72),
                layout.leftWidth - 44, tint = LobbyMuted)

            if ui.selectedSeat >= 0:
              let index = ui.selectedSeat
              if not editable or index notin 0 ..< shownSeats.len:
                ui.selectedSeat = -1
              elif online and (not config.seatEnabled(index) or
                shownSeats[index].owner notin [0'u32, client.participant]):
                  let seat = shownSeats[index]
                  if owner and seat.owner != 0 and
                    (seat.kind == BotSeat or not config.seatEnabled(index)):
                    let choice = sk.removeSeatDialog(window, seat)
                    if choice.chosen:
                      ui.selectedSeat = -1
                      if choice.clear:
                        client.send(RoomMessage(kind: ReleaseSeat, seat: uint32(index)))
                        lobby.policies[index] = LocalPolicy()
                  else:
                    ui.selectedSeat = -1
              else:
                let choice = sk.seatPicker(window, ui, bots)
                if choice.chosen:
                  ui.selectedSeat = -1
                  let selected =
                    if choice.file: selectPolicy()
                    elif choice.clear or choice.human: LocalPolicy()
                    else: bots[choice.bot]
                  if not choice.file or selected.bytes.len > 0:
                    if selected.bytes.len > 0 and
                      not selected.name.roomNameValid:
                        reject("Choose a valid bot name of up to 96 bytes")
                    if online:
                      lobby.joined = true
                      if choice.human:
                        client.claimHuman(index)
                      else:
                        client.send(RoomMessage(
                          kind: if choice.clear: ReleaseSeat else: ClaimSeat,
                          seat: uint32(index), name: selected.name, seatKind: BotSeat
                        ))
                      lobby.policies[index] = selected
                    else:
                      if choice.human:
                        local.human = index
                      elif index == local.human:
                        local.human = -1
                      local.policies[index] = selected

          if page in {MultiplayerMenu, SettingsMenu} and
            not pudgeBindingCapture() and not bindingCapture and
            sk.playerButton(window, preferences.name):
              playerDraft = if needsName: "" else: preferences.name
              editPlayer = true
      except CatchableError as problem:
        error = problem.msg
      if error.len > 0:
        sk.lobbyLabel(error, vec2(24, 0), 1400, tint = LobbyRed)
      sk.textStyle = "Default"
      sk.endUi()
      presentPudgeFrame(framePaceHz)
      reportReplayFrame(0, 0)
      when defined(emscripten):
        if not reportedFrame:
          presentationReady()
          reportedFrame = true
    pollEvents()
    waitForDisplay()
    if launchLocal:
      window.onFrame = nil
      try:
        let
          human = local.human
          name = if preferences.name.confirmedPlayerName: preferences.name
            else: "Player"
          match = newLocalGame(local.config, local.seats(name), human,
            local.policies.sources())
        installGame(match, match.world.worldIndexOfSeat(human))
        error = ""
        let home = runGraphics()
        page = if home: HomeMenu else: SingleMenu
        reloadPreferences()
      except CatchableError as problem:
        error = problem.msg
      releaseGame()
  window.onButtonPress = nil
  window.onFrame = nil
  connection.close()
  lobby.clearRoom()
