# Pudge Wars BASIC episodes and league history

## Local execution after the multiplayer migration

The Pudge Wars relay multiplayer client now handles human rooms. The former
`pwcoworld` server, `/ws` game protocol, `/player` policy socket, `/global`
spectator socket and `coworld/platform-hosted/` package were removed. The
legacy browser and coaching launchers `scripts/play_policy.py`,
`scripts/coach_demo.sh` and `python -m coaching.symbolic.play` used those sockets.
Use the game’s Multiplayer menu for relay play or the Single Player menu for a
local match against BASIC policies.

The `pwleague` executable now runs one staged BASIC episode and exits. Rebuild
it from `examples/pudge_wars/episodes.nim` before using `--binary` with
`scripts/run_episode.py`. Its contract uses local `file://` URIs for the config,
policy seats, failure, results and replay. Staged rosters use
`coworld-player-seats/1` or `coworld-player-seats/2`. The former
`coworld-play-seats/1` roster and collectors depending on a live `/healthz`
endpoint require their original release. Published release IDs and checksums
are recorded in [deployment.json](deployment.json).

Local training uses [the JSONL bridge](TRAINING.md). Symbolic policy evaluation
uses `python3 -m coaching.symbolic.evaluate`. Both use the native simulation and
fog-filtered observations through local subprocesses. Use the replay verifier
from this checkout to inspect newly written episode replays. The viewer pinned
in the historical release record reads the replay format from that release.

The public 3v3 league moved from container players to game-hosted BASIC files
on 2026-10-09. Its 37 container memberships were retired and its three
container fillers were replaced. The historical sibling duel league used the
platform-hosted package. The evidence from that migration is below.

## Player contract

Upload raw BASIC up to 64 KiB or a neural ZIP package up to 16 MiB; the staged
filename has no extension. [Neural tensors and Jev](INFERENCE.md) use the shared
GotA interfaces. Every seat
gets an independent VM; globals, arrays and strings persist between decisions.
The VM has no filesystem access. Host-configured LLM/Jev callbacks use the
platform sidecar with per-seat attribution. The game process can read
all submitted source, as with other game-hosted Coworlds.

Each living seat runs once per simulation tick, in rotating seat order, through
the same fog-clipped host functions and recorded action path as native play.
The simulation is 32 Hz and runs without real-time pacing in league episodes.
The existing integer tile coordinates and gameplay rules are unchanged.

Per-seat limits:

| Resource | Limit |
| --- | --- |
| Source | 64 KiB |
| VM memory | 2 MiB |
| Instructions per decision | 100,000 |
| Work units per decision | 250,000 |
| Globals / arrays / array elements | 256 / 32 / 4,096 |
| Call depth | 16 |
| Strings / string storage / one string | 1,024 / 256 KiB / 64 KiB |
| Native tensor/package storage | 32 MiB per seat |
| PRINT per decision | 1 KiB / 128 events |
| Private episode log | 10 MiB, then truncated |

Bassy supports fixed-point decimals and strings. `/` performs Q16.16 division;
`\` performs integer division. Comparisons return -1 or 0; `and`, `or`, `xor`
and `not` are bitwise. Host flags still return 1 or 0, so negate them with
`flag = 0`. IDs, indices and all Pudge action arguments require exact integers.
Use `(worldTick \ 8) mod 4`, for example. Bundled bots were ported to explicit
integer division to retain their existing decisions. Archived coaching policies
are historical artifacts and need the same source port before use with Bassy.

The complete game API is documented in
[`base.bas`](../examples/pudge_wars/players/base.bas). The bundled policies in
`coworld/players/` must match the corresponding native sources; a test enforces
that equality. Keep both copies updated when changing a bundled bot.

`PRINT`, source diagnostics and VM errors go only to the owning seat's log.
Compile/source-limit errors terminate the episode through
`COGAME_PLAYER_FAILURE_URI` with a zero-based `failed_policy_index`. Runtime
errors disable only that VM; other seats continue, and private status marks the
failed VM. Replay or output-storage errors never publish successful results.
Missing/mismatched staged files are infrastructure failures, not player blame.

The manifest opts into `coworld-player-seats/2`. Each seat can emit optional
private annotations with `ANNOTATE(worldTick, kind$, function$, args$)` where
`args$` is a JSON object string. Zero means accepted; `ANNOTATE_ERROR$()` explains
rejections. Limits are 1,000 records, 2 KiB per record and 2 MiB per episode per
seat. Native play exposes the same functions with annotations disabled. The
annotation sink is ported from the pinned Polyworld `src/polyworld/annotations.nim`.

All logs, annotations, status and replay bytes finish before the runner writes
its atomic results marker and exits. Local callers can wait for process exit
before collecting artifacts.

## League settings

[`league-settings.json`](league-settings.json) records the deployed settings
for the public 3v3 BASIC league using GotA's current competition conventions:

- `team_n`, two teams, contiguous `blocks`, distinct teammates.
- Rating-based `elo_softmax` matchmaking, temperature 100.
- OpenSkill Plackett-Luce, initial mu 25 and sigma 25/3.
- 24 episodes per round, 32-minute interval, separate filler policies.

The BASIC league variant is `league-3v3`: six seats, first to 30, at most 38,400
ticks. `duel-1v1` uses two seats, first to 10, at most 15,360 ticks. Pudge scoring
remains one point per winning seat, zero for a draw/loss. At the time limit, the
bank ahead on kills wins. GotA's XP scoring is specific to that game.

The existing league ID and Competition division were retained. The platform
reset archived 1,155 old rounds and cleared the Elo standings before OpenSkill
was enabled. Historical episode records remain accessible by ID. The seven
uploaded BASIC policies are available for selection, with Base as the owner's
champion and all seven available as unranked fillers. The first round completed
all 24 episodes. Other authors must submit new BASIC or neural package policies.

## Run local BASIC episodes without Docker

`scripts/run_episode.py` uses the staged BASIC loader and native simulation. It accepts bundled names or custom source paths, and expands a trailing
`:COUNT` into independent seats. The first half of the roster is West; the
second half is East. Rosters of 2, 4, 6, 8 and 10 are supported.

```bash
python3 scripts/run_episode.py --list-policies

# Duel; defaults to 15,360 ticks and first to 10.
python3 scripts/run_episode.py base aggressive --seed 7

# Clone teams, 3v3; defaults to 38,400 ticks and first to 30.
python3 scripts/run_episode.py base:3 sniper:3 --seed 29

# Different policy in each seat, with a custom file.
python3 scripts/run_episode.py ./my-policy.bas support patient aggressive denier sniper

# Short development episode using an already built episode runner.
python3 scripts/run_episode.py challenger:2 support:2 \
  --binary tmp/pwleague --ticks 1024 --output tmp/my-episode
```

Bundled names are `base`, `aggressive`, `challenger`, `denier`, `patient`,
`sniper`, `support` and `jev`; `.bas` suffixes also work. Custom paths resolve from
your shell's current directory. Raw BASIC and neural ZIPs are detected by content, regardless of filename
extension. Use `--llm` to enable local host-configured Jev/LLM calls. Old integer-only policies must replace integer `/`
expressions with `\` before using fractional values with integer host arguments.

Without `--binary`, the command compiles a fresh runner using `NIM` or `nim` on
PATH; `--nim /path/to/nim` overrides it. Install the locked dependencies first.
No art, graphics, account, Docker daemon or hosted credits are needed.
`--ticks`, `--kill-goal`, `--seed` and `--timeout` control the episode.

Each run prints its artifact directory (by default a unique directory under
`tmp/episodes/`). It retains `results.json`, `replay.pwr`, `game.log`, private
`players/<slot>/log.txt` and optional annotations, `player_status.json`, the
runner config and seats documents, and `episode.json` with source/binary hashes.
Exact source snapshots live at `players/<slot>/file`. Explicit output directories
must be new or empty. Re-running a roster and seed reproduces results/replay bytes.

Exit codes distinguish success (0), input/build/runner/timeout failures (1),
policy compilation failures (2), and completed games with disabled VMs (3).
Runtime-error episodes retain their results and replay for diagnosis. Timeout
and interruption stop the runner and retain partial artifacts.

To watch or verify a saved replay:

```bash
# Watch with the native graphical client (requires art).
nim c -o:tmp/pw-native examples/pudge_wars/pw.nim
tmp/pw-native --replay tmp/my-episode/replay.pwr

# Headless verification of every recorded tick; no art required.
nim c -d:headless -o:tmp/pwheadless-local examples/pudge_wars/pw.nim
tmp/pwheadless-local --replay tmp/my-episode/replay.pwr
```

## Validate local execution

With Nim 2.2.10 and the locked dependencies installed, run the staged file,
local episode, training and replay test suite.

```bash
bash scripts/test_league.sh
```

Build the local batch image with a running Docker daemon.

```bash
docker compose -f coworld/compose.yaml build
```

The manual episode-image workflow builds the image and runs a short episode
with networking disabled. Its artifact checks use the same local CLI. The
source manifest describes the batch file contract. New hosted certification
would require a compatible batch collector and a replay viewer built for the
current format.

## Historical verification, 2026-10-09

The original migration verified nine Nim suites, six host integration tests,
the local episode command and the training bridge. The local matrix runs every
bundled policy in full duels on both banks, mixed 2v2/3v3/4v4/5v5 rosters,
custom paths, persistent strings/annotations, repeatability and failure cases.
Native graphics compile, and
the WASM target passes `nim check -d:emscripten`. Both package manifests pass
Coworld's Pydantic validation, and the league template passes its ladder model.

The ported bots also match the original VM's final hashes in 12 independent
1,024-tick comparisons: seeds 7 and 29, 1v1/3v3/5v5, and both bank assignments.
The existing combat-policy and economy-policy suites have 12 and 10 failing
strategy cases respectively; running the unchanged HEAD sources reproduces
exactly those failures. They are separate from the passing migration checks.

The 0.1.0 Linux/amd64 image passed local certification, hosted certification,
five hosted smoke episodes and its first 24-episode league round. Neural/Jev
validation passed on 0.1.1, including an actual hosted Jev response and
a hash-exact downloaded replay. [Deployment record](deployment.json) and
[release notes](../docs/hosted-release-basic-0.1.1-2026-10-09.md) retain the IDs.

Platform references:
[Player runtimes](https://github.com/softmax-universe/softmax/blob/d92408b26a/packages/coworld/src/coworld/docs/PLAYER_RUNTIMES.md),
[player seats](https://github.com/softmax-universe/softmax/blob/d92408b26a/packages/coworld/src/coworld/docs/artifacts/PLAYER_SEATS.md),
[GotA guide](https://github.com/softmax-universe/polyworld/blob/743f108091ca20b78f7e3fdc1a42f59ddb4ac795/coworld/gota/guide.md).
