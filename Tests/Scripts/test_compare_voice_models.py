from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts/evals/compare_voice_models.py"
SPEC = importlib.util.spec_from_file_location("compare_voice_models", SCRIPT)
assert SPEC and SPEC.loader
compare_voice_models = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(compare_voice_models)


class CompareVoiceModelsTests(unittest.TestCase):
    def test_models_are_scored_independently_against_human_gold(self) -> None:
        references = [{
            "id": "gold-1", "split": "release-test",
            "reference": "release कब है", "reference_status": "human-confirmed",
            "languages": ["en", "hi"], "condition": "clean",
        }]
        models = {
            "teacher": {"gold-1": {
                "id": "gold-1", "hypothesis": "release कब है", "languages": ["en", "hi"],
            }},
            "student": {"gold-1": {
                "id": "gold-1", "hypothesis": "release है", "languages": ["en", "hi"],
            }},
        }

        report = compare_voice_models.compare_models(references, models)

        self.assertEqual(report["reference_authority"], "human-confirmed")
        self.assertEqual(report["models"]["teacher"]["overall"]["wer"], 0)
        self.assertGreater(report["models"]["student"]["overall"]["wer"], 0)
        self.assertGreater(report["delta_from_best"]["student"]["wer"], 0)

    def test_nonhuman_release_reference_is_rejected(self) -> None:
        references = [{
            "id": "bad", "split": "release-test", "reference": "guess",
            "reference_status": "teacher-consensus",
        }]

        with self.assertRaisesRegex(ValueError, "human-confirmed"):
            compare_voice_models.compare_models(
                references, {"model": {"bad": {"id": "bad", "hypothesis": "guess"}}},
            )

    def test_development_comparison_requires_explicit_override(self) -> None:
        references = [{
            "id": "dev", "split": "development", "reference": "hello",
            "reference_status": "human-confirmed",
        }]

        with self.assertRaisesRegex(ValueError, "release-test"):
            compare_voice_models.compare_models(
                references, {"model": {"dev": {"id": "dev", "hypothesis": "hello"}}},
            )

        report = compare_voice_models.compare_models(
            references,
            {"model": {"dev": {"id": "dev", "hypothesis": "hello"}}},
            allow_development=True,
        )
        self.assertEqual(report["cases"], 1)


if __name__ == "__main__":
    unittest.main()
