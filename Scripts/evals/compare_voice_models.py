#!/usr/bin/env python3
"""Score multiple recognizers independently against frozen human references."""

from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any


QUALITY_SCRIPT = Path(__file__).with_name("voice_quality_eval.py")
QUALITY_SPEC = importlib.util.spec_from_file_location("voice_quality_eval_shared", QUALITY_SCRIPT)
assert QUALITY_SPEC and QUALITY_SPEC.loader
voice_quality_eval = importlib.util.module_from_spec(QUALITY_SPEC)
QUALITY_SPEC.loader.exec_module(voice_quality_eval)


LOWER_IS_BETTER = {
    "wer", "devanagari_cer", "dropped_span_rate", "mean_speaker_count_error",
    "diarization_error_rate", "empty_hypothesis_rate", "warm_latency_p95_ms",
}
HIGHER_IS_BETTER = {"domain_term_recall", "language_sequence_accuracy"}


def compare_models(
    references: list[dict[str, Any]],
    models: dict[str, dict[str, dict[str, Any]]],
    allow_development: bool = False,
) -> dict[str, Any]:
    if not references:
        raise ValueError("at least one reference is required")
    if not allow_development and any(
        reference.get("split") != "release-test" for reference in references
    ):
        raise ValueError("comparison requires release-test rows unless development is explicit")
    if any(
        reference.get("reference_status") != "human-confirmed"
        for reference in references
    ):
        raise ValueError("every comparison reference must be human-confirmed")
    if not models:
        raise ValueError("at least one model is required")

    model_reports = {
        name: voice_quality_eval.build_report(references, hypotheses)
        for name, hypotheses in sorted(models.items())
    }
    overall_by_model = {
        name: report["overall"] for name, report in model_reports.items()
    }
    deltas: dict[str, dict[str, float | None]] = {
        name: {} for name in model_reports
    }
    for metric in sorted(LOWER_IS_BETTER | HIGHER_IS_BETTER):
        available = {
            name: values.get(metric)
            for name, values in overall_by_model.items()
            if isinstance(values.get(metric), (int, float))
        }
        if not available:
            continue
        best = (
            min(available.values())
            if metric in LOWER_IS_BETTER
            else max(available.values())
        )
        for name in model_reports:
            value = available.get(name)
            deltas[name][metric] = None if value is None else (
                value - best if metric in LOWER_IS_BETTER else best - value
            )

    return {
        "reference_authority": "human-confirmed",
        "scope": "development" if allow_development else "release-test",
        "cases": len(references),
        "models": model_reports,
        "delta_from_best": deltas,
    }


def parse_model(value: str) -> tuple[str, Path]:
    name, separator, raw_path = value.partition("=")
    if not separator or not name.strip() or not raw_path.strip():
        raise argparse.ArgumentTypeError("expected NAME=PATH")
    return name.strip(), Path(raw_path)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--model", action="append", type=parse_model, required=True)
    parser.add_argument("--allow-development", action="store_true")
    parser.add_argument("--output", type=Path)
    arguments = parser.parse_args(argv)

    try:
        references = voice_quality_eval.read_jsonl(arguments.manifest)
        models = {
            name: {
                str(row["id"]): row
                for row in voice_quality_eval.read_jsonl(path)
            }
            for name, path in arguments.model
        }
        report = compare_models(
            references, models, allow_development=arguments.allow_development,
        )
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        return 2

    serialized = json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True)
    if arguments.output:
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        arguments.output.write_text(serialized + "\n", encoding="utf-8")
    print(serialized)
    return 0


if __name__ == "__main__":
    sys.exit(main())
