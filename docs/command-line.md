# Command-line options

Pudge Wars uses Polyworld's shared argument parser for common options. Values
accept a separate argument, `=`, or `:`:

```sh
./pw --replay "replays/match.pwr"
./pw --replay="replays/match.pwr"
./pw --replay:"replays/match.pwr"
```

| Option | Behavior |
| --- | --- |
| `--record PATH` | Save the live match to this exact path, creating parent directories. |
| `--replay PATH` | Load and verify a replay instead of running live controllers. |
| `--bot PATH[:N]` | Add N copies of a BASIC bot, in command-line order; N defaults to 1. |
| `--bots PATH[:N]` | The same repeatable bot option. |
| `--player [N]` | Control one one-based slot; a bare flag means slot 1. |
| `--name TEXT` | Set the display name; it does not select a controlled slot. |
| `--seed N` | Select the live match seed. |
| `--ticks N` | Limit a live match to N simulation ticks. |
| `--seconds N`, `--minutes N` | Set the same limit in elapsed simulation time. |
| `--play BOOL` | Start the graphical transport playing or paused. |
| `--speed N` | Set the graphical playback speed. |
| `--windowSize WIDTHxHEIGHT`, `--vsync BOOL` | Configure the native window. |
| `--mute`, `--unmute` | Override the saved audio setting for this launch. |
| `--headless-tick-rate N` | Pace headless simulation at N ticks per second; 0 is unlimited. |
| `--llm-mode async\|barrier` | Advance asynchronously or wait for each tick's bot request batch. |
| `--server URL`, `--room CODE` | Open the multiplayer relay and selected room. |
| `--verbose` | Print additional launch diagnostics. |
| `--screenshot PATH`, `--frames N` | Save a native capture after N rendered frames and exit. |

Pudge Wars runs at 32 simulation ticks per second. A minute is always 60 seconds;
`--minutes 1` therefore means 1920 Pudge Wars ticks. These duration options do not
change the simulation tick rate.

Bots fill the seats not occupied by the human player or Pudge-specific practice
controllers. Repeat bot options to choose different programs. For example:

```sh
./pw --duel --player 1 --bot players/challenger.bas --record replays/duel.pwr
./pwheadless --duel --bots players/challenger.bas:2 --seconds 30 --record replays/bots.pwr
```

Relative bot, replay, and recording paths are resolved from the directory where
the executable is launched. `--record` alone keeps the desktop menu open and
uses that destination when a match starts. It cannot be combined with `--replay`.
Replay playback also rejects live bot and human controller options.
`--server` and `--room` use lobby-selected seats, so they cannot be combined
with local bot, player, or replay launches. They can be combined with `--record`
and `--name`. Headless pacing flags are rejected by graphical builds.

Pudge-specific options such as `--duel`, `--team-size`, and coaching options
remain separate. `--practice-player N` adds another one-based human practice
seat and is repeatable. Use `--player` for ordinary single-player control;
`--human` and `--sound` have been replaced by `--player` and `--unmute`.
