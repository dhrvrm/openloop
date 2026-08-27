from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts/evals/teacher_consensus.py"
SPEC = importlib.util.spec_from_file_location("teacher_consensus", SCRIPT)
assert SPEC and SPEC.loader
teacher_consensus = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(teacher_consensus)


class TeacherConsensusTests(unittest.TestCase):
    def test_exact_agreement_is_eligible_literal_text(self) -> None:
        manifest = [{"id": "one", "split": "distill-train"}]
        sources = {
            "whisper": {"one": {"id": "one", "hypothesis": "नमस्ते Dhruv", "languages": ["hi", "en"]}},
            "cloud": {"one": {"id": "one", "hypothesis": "नमस्ते Dhruv", "languages": ["hi", "en"]}},
        }

        labels, reviews = teacher_consensus.build_consensus(manifest, sources)

        self.assertEqual(reviews, [])
        self.assertEqual(labels[0]["text"], "नमस्ते Dhruv")
        self.assertEqual(labels[0]["label_authority"], "teacher-consensus")
        self.assertTrue(labels[0]["eligible_for_distillation"])

    def test_medoid_is_an_unmodified_submitted_hypothesis(self) -> None:
        manifest = [{"id": "one", "split": "development"}]
        sources = {
            "a": {"one": {"id": "one", "hypothesis": "ship SGLC release", "languages": ["en"]}},
            "b": {"one": {"id": "one", "hypothesis": "ship the SGLC release", "languages": ["en"]}},
            "c": {"one": {"id": "one", "hypothesis": "ship SGLC release", "languages": ["en"]}},
        }

        labels, _ = teacher_consensus.build_consensus(
            manifest, sources, minimum_agreement=0.70,
        )

        self.assertEqual(labels[0]["text"], "ship SGLC release")
        self.assertIn(labels[0]["text"], [
            source["one"]["hypothesis"] for source in sources.values()
        ])

    def test_language_disagreement_requires_review(self) -> None:
        manifest = [{"id": "one", "split": "distill-train"}]
        sources = {
            "a": {"one": {"id": "one", "hypothesis": "release कब है", "languages": ["en", "hi"]}},
            "b": {"one": {"id": "one", "hypothesis": "release कब है", "languages": ["hi"]}},
        }

        labels, reviews = teacher_consensus.build_consensus(manifest, sources)

        self.assertEqual(labels, [])
        self.assertIn("language-sequence-disagreement", reviews[0]["reasons"])
        self.assertFalse(reviews[0]["eligible_for_distillation"])

    def test_missing_or_failed_witness_requires_review(self) -> None:
        manifest = [{"id": "one", "split": "distill-train"}]
        sources = {
            "a": {"one": {"id": "one", "hypothesis": "hello", "languages": ["en"]}},
            "b": {"one": {"id": "one", "hypothesis": "", "error": "decoder failed"}},
        }

        labels, reviews = teacher_consensus.build_consensus(manifest, sources)

        self.assertEqual(labels, [])
        self.assertIn("failed-witness", reviews[0]["reasons"])

    def test_release_test_is_never_teacher_labelled(self) -> None:
        manifest = [{"id": "one", "split": "release-test"}]
        sources = {
            "a": {"one": {"id": "one", "hypothesis": "hello", "languages": ["en"]}},
            "b": {"one": {"id": "one", "hypothesis": "hello", "languages": ["en"]}},
        }

        labels, reviews = teacher_consensus.build_consensus(manifest, sources)

        self.assertEqual(labels, [])
        self.assertEqual(reviews[0]["reasons"], ["held-out-release-test"])


if __name__ == "__main__":
    unittest.main()
