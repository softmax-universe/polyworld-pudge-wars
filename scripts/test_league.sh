#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
unit_only=false
case "${1:-}" in
  --unit) unit_only=true ;;
  "") ;;
  *) echo "Usage: $0 [--unit]" >&2; exit 2 ;;
esac
if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [--unit]" >&2
  exit 2
fi
mkdir -p tmp
unit_cache="${PUDGEWARS_TEST_CACHE:-tmp/nimcache/unit}"
# Test shared UI geometry without requiring native audio libraries.
for test in cli bots sim ejection runes replays chat_replay replay_layout observation_replay observations human duel fileplayers; do
  nim c --hints:off -d:release -d:audioTest --nimcache:"$unit_cache" \
    -o:"tmp/test_pw_${test}" -r "tests/test_pw_${test}.nim"
done
if "$unit_only"; then
  exit 0
fi
nim c --hints:off -d:ssl -d:release -o:tmp/pwleague examples/pudge_wars/episodes.nim
python3 -m unittest discover -s tests -p test_pw_staged_episode.py -v
python3 -m unittest discover -s tests -p test_pw_local_episode.py -v
python3 -m unittest discover -s tests -p test_pw_inference.py -v
nim c --hints:off -d:release -d:headless -o:tmp/pwtraining \
  examples/pudge_wars/training_host.nim
python3 -m unittest discover -s tests -p test_pw_training_bridge.py -v
