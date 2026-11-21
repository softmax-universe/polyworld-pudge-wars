# Pudge Wars investigation bindings

This repository owns the game and its policy sources. These bindings adapt the
installed research skills to Pudge Wars; they do not require the CoGames,
Mettagrid, CogsGuard, or agent-policies repository layouts.

| Binding | Entry point |
| --- | --- |
| `replay-inspection` | [Replay format, viewing and survey](skills/replay-inspection/README.md) |
| `eval-design` | [Hosted comparisons](skills/eval-design/README.md) |
| `diagnosis` | [Failure vocabulary and evidence](skills/diagnosis/README.md) |

Read [META.md](META.md) and [closed_levers.md](closed_levers.md) before proposing
another policy change. The [improvement investigation](../../docs/pudge-improvement-roadmap.md)
records the current findings and next experiments. No automatic deployment or
XP spending is implied by this manifest.

The newer [gameplay skill-gradient investigation](../../docs/gameplay-skill-gradient.md)
covers the current BASIC runtime, local paired-bank evaluation, threat selection,
replay verification and concrete next gameplay experiments.

Run BASIC policies with [the local episode runner](../../coworld/GAME_HOSTED_MIGRATION.md#run-local-basic-episodes-without-docker).
Use the [CoWorld agent guide](../../coworld/README.md) for the hosted fast-XP
workflow. The [version log](players/pudge-wars-rusher/VERSION_LOG.md) records
immutable uploads from past campaigns.
