from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "Evaluation/voice/corpora.json"


class VoiceCorporaCatalogTests(unittest.TestCase):
    def test_every_corpus_has_enforceable_usage_policy(self) -> None:
        document = json.loads(CATALOG.read_text(encoding="utf-8"))

        for corpus in document["corpora"]:
            with self.subTest(corpus=corpus["id"]):
                self.assertIsInstance(corpus["usage_status"], str)
                self.assertTrue(corpus["usage_status"])
                self.assertIsInstance(corpus["license_evidence"], str)
                self.assertTrue(corpus["license_evidence"])
                self.assertIsInstance(corpus["allowed_uses"], list)
                self.assertIsInstance(corpus["forbidden_uses"], list)
                self.assertTrue(corpus["allowed_uses"] or corpus["forbidden_uses"])

    def test_kaggle_entries_pin_slug_and_observed_version(self) -> None:
        document = json.loads(CATALOG.read_text(encoding="utf-8"))
        kaggle = [
            corpus for corpus in document["corpora"]
            if corpus.get("source_kind") == "kaggle"
        ]

        self.assertGreaterEqual(len(kaggle), 3)
        for corpus in kaggle:
            with self.subTest(corpus=corpus["id"]):
                self.assertRegex(corpus["exact_slug"], r"^[^/]+/[^/]+$")
                self.assertRegex(corpus["observed_last_updated"], r"^\d{4}-\d{2}-\d{2}T")

    def test_no_kaggle_audio_is_approved_while_license_is_ambiguous(self) -> None:
        document = json.loads(CATALOG.read_text(encoding="utf-8"))
        ambiguous = [
            corpus for corpus in document["corpora"]
            if corpus.get("source_kind") == "kaggle"
            and corpus["usage_status"] != "evaluation-approved"
        ]

        self.assertTrue(ambiguous)
        for corpus in ambiguous:
            self.assertIn("fine-tuning", corpus["forbidden_uses"])


if __name__ == "__main__":
    unittest.main()
