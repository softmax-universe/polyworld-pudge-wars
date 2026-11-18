# Pudge Wars over Tailscale

After the Games Showcase PR is deployed, open its client with this relay selected:

https://softmax-universe.github.io/gameshowcase/games/pudge-wars/play/?server=wss%3A%2F%2Fwork-computer.tail0f4a29.ts.net%2Fpudge%2Fws

Choose **Multiplayer**, enter your name, then create or join a room. Players
need access to this Tailscale network. The browser files are served by GitHub
Pages; multiplayer runs on `work-computer`, which must remain online and awake.
Single Player does not use the relay.

## Installed relay

The shared Polyworld relay binds to `127.0.0.1:9915`. Tailscale Serve proxies
`/pudge` to that address and terminates HTTPS. The WebSocket endpoint is
`wss://work-computer.tail0f4a29.ts.net/pudge/ws`. This is a tailnet service,
without Tailscale Funnel.

- LaunchAgent: `~/Library/LaunchAgents/com.polyworld.pudge-relay.plist`.
- Binary and build provenance: `~/Library/Application Support/Polyworld/pudge-relay/`.
- Logs: `relay.log` and `relay-error.log` in that directory.
- The agent starts at login and restarts the relay if it exits.

The installed relay uses Polyworld commit
`3cc3a0650008533a1200142bc527a0b9226c7682`, matching `nimby.lock`.
Its server, room protocol, and relay sources are byte-for-byte identical to
upstream `a8cd9868`. It routes protocol 5 packets without interpreting Pudge
rules, configuration, or actions. All game-specific validation is in the client.
The installed `build.json` records the binary checksum and source revisions;
the browser's `build.json` records its matching client build.

## Check the service

```sh
launchctl print "gui/$(id -u)/com.polyworld.pudge-relay"
curl -fsS http://127.0.0.1:9915/healthz
curl -fsS https://work-computer.tail0f4a29.ts.net/pudge/healthz
tailscale serve status
```

The browser integration check opens two clients, exchanges ability commands,
compares simulation hashes, and tests pause, resume, and leaving the match:

```sh
PUDGEWARS_BROWSER_URL=https://softmax-universe.github.io/gameshowcase/games/pudge-wars/play/ \
PUDGEWARS_RELAY_URL=wss://work-computer.tail0f4a29.ts.net/pudge/ws \
node tests/manual_pw_multiplayer_browser.mjs
```

Set `PLAYWRIGHT_MODULE` to an existing Playwright installation if the package
is not on Node's module search path. The test uses installed Google Chrome.

## Rebuild or stop

Follow [the build guide](building.md) with the pinned engine and dependencies
to rebuild the client and `tools/gameserver.nim`. Updating the installed binary
and restarting its LaunchAgent ends any current rooms. The browser bundle is
published under `public/games/pudge-wars/play/` in Games Showcase; the older
replay viewer at `public/games/pudge-wars/` remains independent.

Stop only this relay and remove only its Tailscale route with:

```sh
launchctl bootout "gui/$(id -u)/com.polyworld.pudge-relay"
tailscale serve --bg --https=443 --set-path=/pudge off
```

To start the installed service again:

```sh
launchctl bootstrap "gui/$(id -u)" \
  "$HOME/Library/LaunchAgents/com.polyworld.pudge-relay.plist"
tailscale serve --bg --https=443 --set-path=/pudge http://127.0.0.1:9915
```
