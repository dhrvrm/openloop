from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts/evals/materialize_fleurs_slice.py"
SPEC = importlib.util.spec_from_file_location("materialize_fleurs_slice", SCRIPT)
assert SPEC and SPEC.loader
materialize_fleurs_slice = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(materialize_fleurs_slice)


class MaterializeFleursSliceTests(unittest.TestCase):
    def test_manifest_row_is_frozen_human_gold(self) -> None:
        row = materialize_fleurs_slice.manifest_row(
            "hi_in",
            {"id": 7, "transcription": " ठीक शब्द "},
            "/tmp/7.wav",
            "a" * 64,
        )

        self.assertEqual(row["id"], "fleurs-hi_in-7")
        self.assertEqual(row["reference"], "ठीक शब्द")
        self.assertEqual(row["reference_status"], "human-confirmed")
        self.assertEqual(row["split"], "release-test")
        self.assertEqual(row["languages"], ["hi"])
        self.assertEqual(row["corpus_id"], "fleurs-en-us-hi-in")


if __name__ == "__main__":
    unittest.main()
