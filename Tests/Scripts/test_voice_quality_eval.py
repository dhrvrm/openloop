from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts/evals/voice_quality_eval.py"
SPEC = importlib.util.spec_from_file_location("voice_quality_eval", SCRIPT)
assert SPEC and SPEC.loader
voice_quality_eval = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(voice_quality_eval)


class VoiceQualityEvalTests(unittest.TestCase):
    def test_nearest_rank_percentiles(self) -> None:
        self.assertEqual(voice_quality_eval.percentile([400, 100, 300, 200], 0.50), 200)
        self.assertEqual(voice_quality_eval.percentile([400, 100, 300, 200], 0.95), 400)
        self.assertIsNone(voice_quality_eval.percentile([], 0.95))

    def test_report_separates_cold_load_and_counts_failures(self) -> None:
        references = [
            {"id": "cold", "reference": "hello", "condition": "clean"},
            {"id": "warm", "reference": "नमस्ते", "condition": "clean"},
            {"id": "failed", "reference": "ship it", "condition": "noise-5db"},
        ]
        hypotheses = {
            "cold": {
                "id": "cold", "hypothesis": "hello", "latency_ms": 5_000,
                "cold_start": True,
            },
            "warm": {
                "id": "warm", "hypothesis": "नमस्ते", "latency_ms": 420,
                "cold_start": False,
            },
            "failed": {
                "id": "failed", "hypothesis": "", "latency_ms": 600,
                "cold_start": False, "error": "emptyTranscript",
            },
        }

        report = voice_quality_eval.build_report(references, hypotheses)
        overall = report["overall"]
        self.assertEqual(overall["latency_p95_ms"], 5_000)
        self.assertEqual(overall["warm_latency_p50_ms"], 420)
        self.assertEqual(overall["warm_latency_p95_ms"], 600)
        self.assertEqual(overall["transcription_failures"], 1)
        self.assertAlmostEqual(overall["empty_hypothesis_rate"], 1 / 3)

    def test_warm_latency_gate_exits_two(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            manifest = directory / "manifest.jsonl"
            hypotheses = directory / "hypotheses.jsonl"
            manifest.write_text(
                json.dumps({"id": "one", "reference": "hello", "condition": "clean"}) + "\n",
                encoding="utf-8",
            )
            hypotheses.write_text(
                json.dumps({
                    "id": "one", "hypothesis": "hello", "latency_ms": 700,
                    "cold_start": False,
                }) + "\n",
                encoding="utf-8",
            )
            result = subprocess.run(
                [
                    sys.executable, str(SCRIPT), "--manifest", str(manifest),
                    "--hypotheses", str(hypotheses), "--max-warm-p95-ms", "600",
                ],
                capture_output=True,
                text=True,
                check=False,
            )
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn('"warm_latency_p95_ms": 700.0', result.stdout)
        self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
