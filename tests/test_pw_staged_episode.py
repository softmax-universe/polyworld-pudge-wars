"""Exercise the staged BASIC process and its artifact contract."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]


class StagedEpisodeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binary = Path(os.environ.get("PUDGE_LEAGUE_BINARY", ROOT / "tmp/pwleague")).resolve()
        if not cls.binary.is_file():
            raise RuntimeError("Build pwleague first (see coworld/GAME_HOSTED_MIGRATION.md)")

    def run_episode(self, sources, ticks=128, failure=False, replay_failure=False,
                    failed_slots=()):
        with tempfile.TemporaryDirectory(prefix="pudge-league-") as directory:
            root = Path(directory)
            seats = []
            for slot, source in enumerate(sources):
                player = root / str(slot)
                player.mkdir()
                data = source.encode()
                (player / "file").write_bytes(data)
                seats.append({"slot": slot, "file_uri": (player / "file").as_uri(),
                              "size_bytes": len(data),
                              "content_hash": "sha256:" + hashlib.sha256(data).hexdigest(),
                              "log_uri": (player / "log").as_uri(),
                              "annotations_uri": (player / "annotations.jsonl").as_uri()})
            config = {"tokens": [f"token-{i}" for i in range(len(sources))],
                      "players": [{"name": f"Seat {i}"} for i in range(len(sources))],
                      "seed": 7, "max_ticks": ticks, "kill_goal": 30, "fog": True}
            (root / "config").write_text(json.dumps(config))
            (root / "seats").write_text(json.dumps({"schema": "coworld-player-seats/2",
                "seats": seats, "player_status_uri": (root / "status").as_uri()}))
            env = {key: value for key, value in os.environ.items() if not key.startswith("COGAME_")}
            env.update({"COGAME_CONFIG_URI": (root / "config").as_uri(),
                        "COGAME_PLAYER_SEATS_URI": (root / "seats").as_uri(),
                        "COGAME_RESULTS_URI": (root / "results").as_uri(),
                        "COGAME_SAVE_REPLAY_URI": (root / "replay").as_uri(),
                        "COGAME_PLAYER_FAILURE_URI": (root / "failure").as_uri(),
                        "COGAME_LLM": "off"})
            if replay_failure:
                (root / "blocked").write_text("not a directory")
                env["COGAME_SAVE_REPLAY_URI"] = (root / "blocked/replay").as_uri()
            process = subprocess.run([str(self.binary)], env=env, cwd=ROOT,
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                     text=True, timeout=90)
            self.assertNotIn("PRIVATE_SENTINEL", process.stdout)
            if replay_failure:
                self.assertFalse((root / "results").exists())
                self.assertNotEqual(process.returncode, 0)
                return
            self.assertEqual(process.returncode, 2 if failure else 0, process.stdout)
            status = json.loads((root / "status").read_text())
            self.assertEqual([seat["slot"] for seat in status["players"]
                              if seat["exit_code"] != 0], list(failed_slots))
            for seat in seats:
                self.assertTrue((root / str(seat["slot"]) / "log").is_file())
            if failure:
                error = json.loads((root / "failure").read_text())
                self.assertEqual(error["failed_policy_index"], 1)
                self.assertFalse((root / "results").exists())
            else:
                result = json.loads((root / "results").read_text())
                self.assertEqual(len(result["scores"]), len(sources))
                self.assertTrue((root / "replay").read_bytes().startswith(b"POLYWORLDREPLAY"))

    def test_full_six_seat_episode(self):
        self.run_episode([(ROOT / f"coworld/players/{name}.bas").read_text()
                          for name in ["base", "aggressive", "sniper"] * 2], ticks=38400)

    def test_private_logs_and_disabled_runtime(self):
        self.run_episode(['print "PRIVATE_SENTINEL"', "while 1\nwend"], failed_slots=[1])

    def test_compile_failure(self):
        self.run_episode(["x = 1", "PRIVATE_SENTINEL invalid syntax"], failure=True,
                         failed_slots=[1])

    def test_replay_failure_does_not_publish_success(self):
        self.run_episode(["x = 1", "x = 2"], replay_failure=True)

    def test_bundled_players_match_local_sources(self):
        manifest = json.loads((ROOT / "coworld/coworld_manifest_template.json").read_text())
        for player in manifest["player"]:
            if player["id"] == "neural":
                with zipfile.ZipFile(ROOT / "coworld" / player["file"]) as archive:
                    self.assertEqual(archive.read("policy.bas"), (ROOT / "examples/pudge_wars/players/neural.bas").read_bytes())
                continue
            self.assertEqual((ROOT / "coworld" / player["file"]).read_bytes(),
                             (ROOT / "examples/pudge_wars" / player["file"]).read_bytes())

if __name__ == "__main__":
    unittest.main()
