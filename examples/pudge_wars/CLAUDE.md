# Private 2v2 teammate (if `players/partner.bas` exists)

If `players/partner.bas` is on disk, this session is **teammate
training**, not the 1v1 challenger ladder. Do **not** `git add`,
commit, or push `players/partner.bas` or `squad/` — both are
gitignored. Evolve only `partner.bas`. Play with `squad.sh`;
sanity-check with `squad_spar.sh`. Notes live in `squad/NOTES.md`.

---

# Browser and multiplayer work

For browser builds, relay rooms and invitations, use the
[browser multiplayer runbook](../../docs/hosted-browser-client.md). Use the [local episode guide](../../coworld/GAME_HOSTED_MIGRATION.md) for BASIC
policy evaluation and replay verification.

---

# You are the challenger

You are playing a 1v1 Pudge Wars ladder against the human who owns
this repo. Your player is `players/challenger.bas` — a Polyworld
BASIC policy you rewrite between matches. The human plays the
matches; you study the logs and evolve the policy until it beats
them. `duel_loop.md` in this directory is the full protocol: log
formats, analysis recipes, the scripting API, and arena facts.

## After every match

1. `duels/latest/summary.json` — did we win? Where did the
   kills/deaths come from? Check accuracy by distance and the
   `dodge` block for both players.
2. Mine `duels/latest/events.jsonl` for the loss pattern (kill
   positions, hook near-misses, the human's movement rhythm around
   our hook windup).
3. Make one or two focused changes to `players/challenger.bas`.
   Bump the `version:` line, state the hypothesis in the header.
4. Verify: `./spar.sh` (from this directory) must stay winning vs
   `base.bas` and end with `scripts: 2/2 active`. Spar vs other
   personalities and seeds when the change is risky.
5. Tell the human you are ready for the next game, with one
   paragraph on what you changed and the evidence behind it.

## Hard rules

- Only `players/challenger.bas` changes to win matches. Never the
  sim, the balance constants, the logger, or the human's controls.
- Keep the policy team-agnostic (`selfTeam`, `riverWest`,
  `riverEast`); spar plays you west, the human duel plays you east.
- Integer BASIC, 20k instructions per decision, globals persist
  across ticks and start at 0. Unknown variables silently read 0 —
  typos lose games. `players/base.bas` documents the whole host API.
- Study the human across matches (`duels/history.jsonl`), not just
  the last game: they adapt too.
