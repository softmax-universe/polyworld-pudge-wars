# PolyWorld — Pudge Wars

Pudge Wars is a river arena where two banks of butchers fight to a kill goal
with a skillshot meat hook, grapple, blink and Rot. It uses the shared Polyworld
engine for native and browser play, with a deterministic 32 Hz simulation,
BASIC bots and shared-relay multiplayer.

Engine design: [docs/engine-design.md](docs/engine-design.md).

## IDE, Hermes and fast-XP context

Start with the [CoWorld agent guide](coworld/README.md) for the game-owned site,
published IDE/Hermes context and the dedicated BASIC fast-XP service. The live
[context index](https://pudge-wars-site-theta.vercel.app/llms.txt) links the complete
experiment workflow and a JSON bundle with document hashes. Fast-XP runs through
https://fast-xp-k8s-prod.tail0f4a29.ts.net/ with Softmax Tailscale access.

## CoWorld package

The BASIC batch runner supports staged source and neural policy packages,
private seat logs and annotations, and replay artifacts. See the
[migration guide](coworld/GAME_HOSTED_MIGRATION.md) for the local runner
contract and the history of the published leagues.

Run local BASIC episodes without Docker:

```bash
python3 scripts/run_episode.py base aggressive          # 1v1
python3 scripts/run_episode.py base:3 sniper:3 --seed 29 # 3v3
python3 scripts/run_episode.py ./my-policy.bas support  # custom policy
```

The command builds the episode runner, runs to the kill goal or time limit, and
saves results, replay, policy snapshots and per-seat logs under `tmp/episodes/`.
Use `--binary tmp/pwleague` to reuse a build, `--ticks 1024` for a short episode,
or `--list-policies` to see the bundled policies. See the
[local episode guide](coworld/GAME_HOSTED_MIGRATION.md#run-local-basic-episodes-without-docker).

## What's here

| Path | What it is |
|---|---|
| `src/pudgewars/` | Game-specific CLI and HUD helpers |
| `examples/pudge_wars/` | Simulation, bots, graphics, frontend and multiplayer adapter |
| `tests/test_pw_*.nim` | Simulation, bots, replays, frontend and relay adapter tests |
| `scripts/setup.sh` | Installs Nimby, Nim 2.2.10, and the pinned packages |
| `nimby.lock` | Pinned shared Polyworld and Nim package commits |

Dependency order inside the game:

`content` → `replays` → `maps` → `sim` → `bots` → `game` → `graphics`

| File | Role |
|---|---|
| `content.nim` | Balance constants (tick rate, roster, kill goal, runes). No art. |
| `maps.nim` | Deterministic river/bank geometry |
| `sim.nim` | Authoritative world tick (fixed-point, float-free) |
| `bots.nim` | BASIC host API the `.bas` policies call |
| `game.nim` | CLI, match setup, headless runner |
| `human.nim` | Mouse/keyboard → the same `record`/`apply` path bots use |
| `graphics.nim` / `ui.nim` | Client only |
| `frontend.nim` | Home, settings, local setup, room browser and lobby |
| `multiplayer.nim` | Pudge Wars simulation and commands through the shared relay |
| `episodes.nim` / `observations.nim` | Staged BASIC episodes and local JSON policy interfaces |
| `players/*.bas` | Bot personas. Base and Rusher use the retained v16 Python strategy ported to BASIC. |

## Requirements

- macOS or Linux
- `curl`, `git`, a C compiler (`clang` on macOS, `gcc`/`clang` on Linux)
- OpenAL: system framework on macOS; `libopenal-dev` (Debian/Ubuntu) on Linux
- Optional, for browser clients: [Emscripten](https://emscripten.org) with `emcc` on `PATH`

## Setup

Follow [Build and run Pudge Wars](docs/building.md) for the shared Polyworld
checkout, Nim 2.2.10, art, and native or WebAssembly builds.

## Play

From the repository root, build and open the native game. Choose **Single
Player** for a local match with BASIC bots or **Multiplayer** for relay rooms.

```bash
nim c -d:release -o:pw examples/pudge_wars/pw.nim
./pw
```

Run `./pw --human` to start a local match directly, or see the
[browser multiplayer runbook](docs/hosted-browser-client.md) to play online.

Headless (no window; CI and bot pacing):

```bash
nim c -d:release -d:headless -o:pwheadless examples/pudge_wars/pw.nim
./pwheadless --seed 7 --record /tmp/demo.pwr
nim r examples/pudge_wars/pw.nim --replay /tmp/demo.pwr
```

## Practice with a decision model, natively

The desktop app and `./pw --human --practice` run a coach on your seat with
no browser or server. A plate in the top-left corner shows the next move the
model recommends, why, the key to use, and the plan for the next few
exchanges. Low-health, hooked and incoming-hook cues are decided locally and
always win. `P` hides the plate; the trace keeps recording.

When the cue is a hook, the coach also marks **where to throw** in the
world, every frame: a ring the size of your hook head at the point where a
throw started now would meet the target, a stroke from where they stand to
that point showing the lead, and a thin line from you. The ring is green
when the throw would land (in range, clear line), ember when the line is
blocked or they are out of reach, and faint when the coach has not called
that target yet but your hook is ready and an enemy is open. The plate's
line under the key reads the same marker: "Throw at the marker, 3 tiles
ahead of them, lands in 0.9 s". The marker steps the real launch profile
(windup, acceleration to the speed cap) against the target's motion, so a
hooked enemy being reeled is led along the reel. Pilots aim at the same
point.

`--coach` picks the model behind the coach and the pilots:

| `--coach` | Endpoint | Key | Default model |
|---|---|---|---|
| `jev` (default) | `https://api.typesafe.ai/v1/systemone` | `typesafe.key` or `TYPESAFE_API_KEY` | `jev-latest` (`TYPESAFE_MODEL`) |
| `d1` | `https://api.liquid.ai/decisions/v1/systemone` | `liquid.key` or `LIQUID_API_KEY` | `d1` (`LIQUID_MODEL`) |
| `local` | `http://127.0.0.1:8765/v1/systemone` | none | whatever the sidecar serves |
| a URL | that base URL (loopback or one of the above hosts) | `COACH_API_KEY` | `--coach-model` |

Key files live in `~/Library/Application Support/Pudge Wars/`, one line each
(a repository `.env.local` also works from the checkout). Without a key the
coach gives local cues only and says so. `--coach-model NAME` overrides the
model name. The local sidecar is `d1/serve.py` in the Co-play Notes
repository: the open `LiquidAI/d1-3B`, or a fine-tune of it, on this machine.

### Pilots: the model plays a seat

`--pilot[:SLOT]` (repeatable) seats the decision model on a butcher. Every
second it is asked the same two Choice questions as the coach, and its answer
is executed through the human intent queue: a hook option becomes a
fine-aimed hook with a little lead, retreat and heal walk home, regroup
closes toward a teammate, reposition and scout move along the river lip,
dodge steps off a flying hook's line, upgrade spends the point. Without a
model (or a confident answer) the pilot takes the first local cue, so it
always plays. Pilots combine with `--human`, with each other, and with bots
on the remaining seats; `--human` alone keeps you as the local seat, pilots
alone spectate.

```bash
./pw --human --practice --coach local --pilot:1 --pilot:2   # the model as your teammates and coach
./pw --pilot:0 --pilot:1 --pilot:2 --coach d1 --seconds 120  # headless: D1 vs the stock bots
```

Headless matches wait for each pilot's answer, so self-play is paced by the
model, not the clock. The graphical client never blocks a frame: a pilot acts
when its answer lands.

### Traces

Every coached or piloted seat writes a decision trace under
`~/Library/Application Support/Pudge Wars/practice/<timestamp>/`
(`--practice-dir DIR` moves it; pilots write `pilot-<slot>/` inside):

| File | What it holds |
|---|---|
| `match.json` | Wall-clock start (`started_ms`), seat, actor (`human` or `pilot`), model, endpoint, map seed. |
| `samples.jsonl` | One record per one-second window: `at_ms`, the fog-clipped observation, the exact request sent (minus the observation) so the prompt can be re-rendered byte for byte, the eligible options, the model's choice with its probabilities and latency, the cue shown or executed, and the intent the seat actually issued. |
| `intents.jsonl` | Every drained intent for the seat with its tick, `at_ms` and engine acceptance. |
| `summary.json` | Reads, agreement with the model, hooks thrown and landed, kills, deaths, requests, failures, and the match result. |
| `replay.pwr` | The exact action tape for the whole match, so any later observation encoding can be re-simulated from it. |

Human intents come straight from the sim's drained queue, so a sample's
`human.id` is an exact decision, not an inference from video. Hooks and
rescues close a window at once; a walk-only window closes with its last walk
class (retreat, heal, regroup, scout, reposition); a quiet window closes as
`none`. For a pilot, `cue` is the decision it executed and agreement compares
that with the model's answer. The wall-clock stamps let Co-play Notes line
these windows up with spoken or typed coaching and turn a correction into a
training label; `d1/` in that repository builds the dataset, trains D1 and
serves it back to `--coach local`.

Headless contracts: `nim r -d:headless tests/test_pw_practice.nim`.

## Mac desktop app

Build a self-contained app with the native game, assets, and BASIC policies:

```bash
examples/pudge_wars/macos/build_app.sh
open "tmp/desktop/Pudge Wars.app"
```

Opening the app shows the home screen. Single Player works from the installed
bundle. To launch a coached local match directly, pass the practice flags with
`open "tmp/desktop/Pudge Wars.app" --args --human --practice --coach local`.
Logs are saved to `~/Library/Logs/Pudge Wars/game.log`.

## Controls

Local matches with a human and shared-relay rooms run at **28 ticks per wall
second**. Hooks, movement, cooldowns and the match clock share this pace.
Offline bot-only matches and normal replay playback use the 32 Hz simulation
clock. Match limits are simulation time, so a timed human match takes 8/7 of
the displayed duration in wall time.

For choppy native graphics on a laptop, try a smaller window with dynamic
shadows disabled. This changes rendering cost separately from the game clock:

```sh
SUN_SHADOWS=0 ./pw --human --windowSize 1280x800
```

The default players use the customized red and blue butcher. Preview and
compare all nine motion clips independently with `./char_viewer`; build and
controls are in [Butcher workshop](examples/pudge_wars/BUTCHER_WORKSHOP.md).

| Input | Action |
|---|---|
| Right click / WASD | Move |
| Q | Meat Hook (aim with cursor) |
| E | Grapple |
| F | Blink |
| R | Rot |
| X | Stop |
| 1–4 | Spend kill points on hook upgrades |
| G | Ping · F1 center · L follow · T take-over · M mute |
| F3 | Debug / fog overlay |
| F9 / F10 | In-game menu / team panel |

`--keys FILE` rebinds with windy names, one `action = KeyName` per line.

## Play with friends

Connect to a shared Polyworld relay from **Multiplayer**. Join a public room,
create a public or private room, or paste an invite. The owner starts the match
once both banks have a controller. The
[browser multiplayer runbook](docs/hosted-browser-client.md) covers relay setup,
native and browser invitations, spectators and rematches.

Run the local simulation and batch evaluation suite with
`bash scripts/test_league.sh`. Test the Pudge relay adapter and lobby setup with
`nim r tests/test_pw_multiplayer.nim` and `nim r tests/test_pw_frontend.nim`.

## License

MIT. See [LICENSE](LICENSE). Check the asset notices alongside the game art.

Neural ZIP policies and Jev judgments are supported through the shared GotA
interfaces; see [inference setup and examples](coworld/INFERENCE.md).
