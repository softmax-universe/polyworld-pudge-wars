#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p tmp
for test in bots sim ejection runes replays chat_replay replay_layout observation_replay observations human duel fileplayers; do
  nim c --hints:off -d:release -o:"tmp/test_pw_${test}" -r "tests/test_pw_${test}.nim"
done
nim c --hints:off -d:ssl -d:release -o:tmp/pwleague examples/pudge_wars/episodes.nim
python3 -m unittest discover -s tests -p test_pw_staged_episode.py -v
python3 -m unittest discover -s tests -p test_pw_local_episode.py -v
python3 -m unittest discover -s tests -p test_pw_inference.py -v
nim c --hints:off -d:release -d:headless -o:tmp/pwtraining \
  examples/pudge_wars/training_host.nim
python3 -m unittest discover -s tests -p test_pw_training_bridge.py -v
