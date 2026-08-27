from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts/evals/export_distillation_dataset.py"
SPEC = importlib.util.spec_from_file_location("export_distillation_dataset", SCRIPT)
assert SPEC and SPEC.loader
export_distillation_dataset = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(export_distillation_dataset)


class ExportDistillationDatasetTests(unittest.TestCase):
    def test_only_approved_or_consented_training_rows_are_exported(self) -> None:
        manifest = [
            {
                "id": "public-ok", "audio": "public.wav", "audio_sha256": "a" * 64,
                "split": "distill-train", "corpus_id": "approved", "languages": ["pa"],
            },
            {
                "id": "private-gold", "audio": "private.wav", "audio_sha256": "b" * 64,
                "split": "distill-train", "source": "private", "training_consent": True,
                "reference": "जो कहा वही", "reference_status": "human-confirmed",
                "languages": ["hi"],
            },
            {
                "id": "pending", "audio": "pending.wav", "audio_sha256": "c" * 64,
                "split": "distill-train", "corpus_id": "pending", "languages": ["pa"],
            },
            {
                "id": "release", "audio": "release.wav", "audio_sha256": "d" * 64,
                "split": "release-test", "corpus_id": "approved", "languages": ["en"],
                "reference": "never train", "reference_status": "human-confirmed",
            },
            {
                "id": "review", "audio": "review.wav", "audio_sha256": "e" * 64,
                "split": "distill-train", "corpus_id": "approved", "languages": ["en"],
            },
        ]
        labels = {
            "public-ok": {
                "id": "public-ok", "text": "ਸਤ ਸ੍ਰੀ ਅਕਾਲ", "languages": ["pa"],
                "eligible_for_distillation": True, "label_authority": "teacher-consensus",
            },
            "pending": {
                "id": "pending", "text": "ਸਤ ਸ੍ਰੀ ਅਕਾਲ", "languages": ["pa"],
                "eligible_for_distillation": True, "label_authority": "teacher-consensus",
            },
            "release": {
                "id": "release", "text": "never train", "languages": ["en"],
                "eligible_for_distillation": True, "label_authority": "teacher-consensus",
            },
            "review": {
                "id": "review", "text": "uncertain", "languages": ["en"],
                "eligible_for_distillation": False, "label_authority": "teacher-consensus",
            },
        }
        catalog = {
            "approved": {"usage_status": "evaluation-approved", "allowed_uses": ["fine-tuning-with-attribution"]},
            "pending": {"usage_status": "pending-license-resolution", "allowed_uses": ["metadata-catalog"]},
        }

        exported, excluded = export_distillation_dataset.export_rows(
            manifest, labels, catalog,
        )

        self.assertEqual([row["id"] for row in exported], ["public-ok", "private-gold"])
        self.assertEqual(exported[0]["text"], "ਸਤ ਸ੍ਰੀ ਅਕਾਲ")
        self.assertEqual(exported[1]["label_authority"], "human-confirmed")
        self.assertEqual(
            {row["id"]: row["reason"] for row in excluded},
            {
                "pending": "corpus-not-approved-for-fine-tuning",
                "release": "held-out-split",
                "review": "teacher-review-required",
            },
        )

    def test_private_audio_requires_explicit_training_consent(self) -> None:
        manifest = [{
            "id": "private", "audio": "private.wav", "audio_sha256": "a" * 64,
            "split": "distill-train", "source": "private",
            "reference": "hello", "reference_status": "human-confirmed",
        }]

        exported, excluded = export_distillation_dataset.export_rows(manifest, {}, {})

        self.assertEqual(exported, [])
        self.assertEqual(excluded[0]["reason"], "private-training-consent-required")


if __name__ == "__main__":
    unittest.main()
