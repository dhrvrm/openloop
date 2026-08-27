from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts/evals/voice_corpus_guard.py"
SPEC = importlib.util.spec_from_file_location("voice_corpus_guard", SCRIPT)
assert SPEC and SPEC.loader
voice_corpus_guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(voice_corpus_guard)


class VoiceCorpusGuardTests(unittest.TestCase):
    def test_valid_manifest_reports_partition_counts(self) -> None:
        rows = [
            {
                "id": "train-1", "audio": "train.wav", "split": "distill-train",
                "audio_sha256": "a" * 64, "speaker_ids": ["speaker-train"],
            },
            {
                "id": "dev-1", "audio": "dev.wav", "split": "development",
                "audio_sha256": "b" * 64, "speaker_ids": ["speaker-dev"],
            },
            {
                "id": "release-1", "audio": "release.wav", "split": "release-test",
                "audio_sha256": "c" * 64, "speaker_ids": ["speaker-release"],
                "reference": "literal words", "reference_status": "human-confirmed",
            },
        ]

        report, errors = voice_corpus_guard.validate_rows(rows, Path("."))

        self.assertEqual(errors, [])
        self.assertEqual(report["rows_by_split"], {
            "development": 1, "distill-train": 1, "release-test": 1,
        })

    def test_release_reference_must_be_human_confirmed(self) -> None:
        rows = [{
            "id": "release-1", "audio": "release.wav", "split": "release-test",
            "audio_sha256": "a" * 64, "speaker_ids": ["speaker-release"],
            "reference": "teacher guessed this", "reference_status": "teacher-consensus",
        }]

        _, errors = voice_corpus_guard.validate_rows(rows, Path("."))

        self.assertIn(
            "release-1: release-test requires a human-confirmed reference", errors,
        )

    def test_audio_hash_cannot_cross_partitions(self) -> None:
        rows = [
            {
                "id": "train-1", "audio": "train.wav", "split": "distill-train",
                "audio_sha256": "a" * 64, "speaker_ids": ["speaker-train"],
            },
            {
                "id": "release-1", "audio": "release.wav", "split": "release-test",
                "audio_sha256": "a" * 64, "speaker_ids": ["speaker-release"],
                "reference": "literal", "reference_status": "human-confirmed",
            },
        ]

        _, errors = voice_corpus_guard.validate_rows(rows, Path("."))

        self.assertTrue(any("audio hash appears across splits" in error for error in errors))

    def test_release_speakers_are_held_out_from_training(self) -> None:
        rows = [
            {
                "id": "train-1", "audio": "train.wav", "split": "distill-train",
                "audio_sha256": "a" * 64, "speaker_ids": ["dhruv"],
            },
            {
                "id": "release-1", "audio": "release.wav", "split": "release-test",
                "audio_sha256": "b" * 64, "speaker_ids": ["dhruv"],
                "reference": "literal", "reference_status": "human-confirmed",
            },
        ]

        _, errors = voice_corpus_guard.validate_rows(rows, Path("."))

        self.assertIn("speaker dhruv appears in distill-train and release-test", errors)


if __name__ == "__main__":
    unittest.main()
