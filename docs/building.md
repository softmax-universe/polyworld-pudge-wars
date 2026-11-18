# Build and run Pudge Wars

Run the commands from the Pudge Wars checkout. The relay client currently
requires the paired local Polyworld checkout at
`7b014a3e8a3bdef4d34fdd8b6debb94786245447`, the revision in `nimby.lock`.
Point `PUDGEWARS_POLYWORLD` at that checkout for setup and all builds until
the shared commit is published. `scripts/setup.sh` uses the supplied engine
and installs Nim 2.2.10 and the remaining locked packages.

```sh
export PUDGEWARS_POLYWORLD=/path/to/polyworld-pudge-multiplayer
scripts/setup.sh
export PATH="$HOME/.nimby/nim/bin:$HOME/.local/bin:$PATH"
export PUDGEWARS_DEPS="${NIMBY_HOME:-$HOME/.nimby}/pkgs"
```

## Art

The native client reads `../polyworld_art` relative to its working directory.
The browser and macOS packaging scripts use `POLYWORLD_ART` when set, then
`build/polyworld_art` if present, then the sibling `../polyworld_art` checkout.
The required entries are in [webdata.txt](../examples/pudge_wars/webdata.txt).

If shared art is installed but lacks the Pudge Wars models, sounds, or terrain,
recover the original files from a local copy of the published browser viewer.
The directory must include the matching `pw.js` and `pw.data` files.

```sh
python3 scripts/recover_art.py ../gameshowcase/public/games/pudge-wars
```

The recovery tool extracts the indexed files, fills missing manifest entries
and shared UI icons from the sibling art checkout, and stages the result in
`build/polyworld_art`.
It also copies the viewer's asset license notice when present. Use
`--shared-art /path/to/polyworld_art` to select the supplement directory.

The verified local source was the Games Showcase viewer for Pudge Wars BASIC
0.1.9, built from Pudge Wars source revision
`cd8111a5ee4f2fdc38c027615b33421f6c7d2536`. Its `viewer-build.json` and
`provenance.txt` describe the source release and repackaging.

| File | SHA-256 |
| --- | --- |
| `pw.js` | `aef1914bab4dff8f53f44e5b4d1cad255df5428026a2306fe8d9011c06d4f30b` |
| `pw.data` | `6aefcfadfe054810b0ed6b0516c190d7b34fe86630ebfeca0dd08968c50b345f` |

## Native client

```sh
mkdir -p build
nim c -o:build/pw examples/pudge_wars/pw.nim
```

Run `./build/pw` from the checkout when its sibling art directory is complete.
For recovered art, use `build/run` as the working directory. The `examples`
link provides the source-relative paths used by optional CLI modes.

```sh
mkdir -p build/run
test -e build/run/examples || ln -s ../../examples build/run/examples
(cd build/run && ../pw)
```

For a standalone macOS app, run `examples/pudge_wars/macos/build_app.sh`.
The signed bundle opens at the home screen and contains the required art and
stock policies.

```sh
open "tmp/desktop/Pudge Wars.app"
```

## Browser client

With Emscripten's `emcc` on `PATH`, build the WebAssembly client and serve it
from localhost.

```sh
bash coworld/tools/build_replay_viewer.sh "$PWD/build/pw-web"
python3 -m http.server 8080 --bind 127.0.0.1 --directory build/pw-web
```

Open [Pudge Wars on localhost](http://127.0.0.1:8080/).

## Multiplayer relay

In a separate terminal, use the same `PUDGEWARS_POLYWORLD` and
`PUDGEWARS_DEPS` settings. Build and start the relay from the paired checkout.

```sh
cd "$PUDGEWARS_POLYWORLD"
mkdir -p build
POLYWORLD_DEPS="$PUDGEWARS_DEPS" nim c -o:build/gameserver tools/gameserver.nim
./build/gameserver
```

The default endpoint is `ws://127.0.0.1:8090/ws`. Open Multiplayer and enter
the relay address and your player name. Clients on different machines need
a relay address they can all reach.

See [Tailscale deployment](tailscale.md) for the installed `work-computer`
relay and its Games Showcase client.
