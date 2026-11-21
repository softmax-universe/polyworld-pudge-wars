# Pudge Wars browser multiplayer

The browser loads a static WebAssembly bundle. The shared Polyworld gameserver
relays multiplayer rooms for both browser and native clients. The game client
runs the match simulation and any BASIC policies assigned to its seats.

The relay routes opaque setup bytes, typed seat assignments, and commands using
Polyworld room protocol 5. Pudge's bank layout, valid starting roster, private
policies, match duration, and command semantics are checked by the game client.
The server has no Pudge-specific rules or code. Ready is a cosmetic status;
the owner starts the exact current room setup without a readiness gate.

Ten stable routing slots reserve five positions per bank. The selected bank
size controls which positions can start the match. Occupied initial slots keep
their butcher when control changes; a newly occupied slot enters gameplay on
the next match. Leaving a running match releases its seats and other players
continue. An invalid command or failed policy stops the match explicitly.

## Run locally

Follow [Build and run Pudge Wars](building.md) to build and serve the browser
bundle and start the shared relay from the pinned Polyworld checkout. The
standalone commands in that guide use `http://127.0.0.1:8080/` for the game and
`ws://127.0.0.1:8090/ws` for the relay. Open **Single Player** to play locally.

1. Open **Multiplayer**, enter a player name and the relay address, and select
   **Connect**. The **Public Rooms** list shows compatible rooms on that relay.
2. Select **Join** for an open room, or create one with **Public** or **Private**
   visibility. A private room is shared by invitation.
3. Use **Copy invite** in the lobby. A browser invitation opens the game and
   joins the room. You can also paste the link or room code into **Join by
   Invite** in a running browser or native client.
4. Choose a seat on either bank. The owner can use **Apply Settings** to
   submit roster and match changes. Place a human or BASIC controller on each
   bank, then the owner can select **Start Game**. Use **Watch** in the room
   list to spectate a match in progress.

For a smoke check, use two independent browser profiles or one native client
and one browser. Join the same room, claim opposite banks, and verify that
movement and hooks appear in both clients. Try an invite to a private room,
watch an active public room, and use **Return to lobby** to start a rematch.

## Serve the bundle for other players

Publish the entire generated directory, including `index.html`, `pw.js`,
`pw.wasm`, `pw.data`, bundled JavaScript and asset notices. Serve the WASM file
as `application/wasm`. The generated invite uses the browser's game URL and
its configured relay address, so give players addresses they can all reach.

Use a `wss://` relay address with a trusted certificate when serving the game
over HTTPS. If the site has a Content Security Policy, permit the relay in
`connect-src` and allow WebAssembly compilation with `wasm-unsafe-eval` in
`script-src`. Keep the client bundle and relay on the compatible shared
Polyworld revision.

## Check replay playback

The shared browser loader defaults to a 64 MiB replay byte limit. A game's
HTML shell can set `Module.polyworldMaxReplayBytes` to a positive integer
before loading its compiled JavaScript. The limit applies to both downloaded
bytes and decompressed bytes, and is independent of server match duration.
Pudge keeps the default because its own replay decoder also accepts at most
64 MiB. Other games can choose a budget suited to their decoder and browser
memory requirements.

An existing Playwright/Chromium installation can run the browser replay test
under a restrictive Content Security Policy. Use a supported replay containing
at least 64 recorded ticks.

```sh
node tests/test_pw_replay_browser.mjs build/pw-web /path/to/episode.pwr
```

Set `PLAYWRIGHT_MODULE` to the path of an installed Playwright module if Node
cannot resolve it. Set `PLAYWRIGHT_CHROMIUM_CHANNEL=chrome` to use system Chrome.

[Local BASIC episodes](../coworld/GAME_HOSTED_MIGRATION.md#run-local-basic-episodes-without-docker)
can produce a replay for the test.
