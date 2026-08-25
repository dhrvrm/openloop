#!/usr/bin/env python3
"""Score immutable OpenLoop voice references against exported hypotheses."""

from __future__ import annotations

import argparse
import itertools
import json
import math
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for number, line in enumerate(handle, start=1):
            value = line.strip()
            if not value or value.startswith("#"):
                continue
            row = json.loads(value)
            if not isinstance(row, dict) or not str(row.get("id", "")).strip():
                raise ValueError(f"{path}:{number}: each row needs a non-empty id")
            rows.append(row)
    return rows


def normalized_tokens(text: str) -> list[str]:
    tokens: list[str] = []
    current: list[str] = []
    for character in unicodedata.normalize("NFKC", text).casefold():
        if character.isalpha() or character.isdigit():
            current.append(character)
        elif current:
            tokens.append("".join(current))
            current = []
    if current:
        tokens.append("".join(current))
    return tokens


def devanagari_characters(text: str) -> list[str]:
    return [
        value
        for value in unicodedata.normalize("NFC", text)
        if "\u0900" <= value <= "\u097f" or "\ua8e0" <= value <= "\ua8ff"
    ]


def edit_distance(source: list[Any], target: list[Any]) -> int:
    if not source:
        return len(target)
    previous = list(range(len(target) + 1))
    for source_index, source_value in enumerate(source, start=1):
        current = [source_index]
        for target_index, target_value in enumerate(target, start=1):
            current.append(min(
                previous[target_index] + 1,
                current[target_index - 1] + 1,
                previous[target_index - 1] + (source_value != target_value),
            ))
        previous = current
    return previous[-1]


def lcs_length(source: list[Any], target: list[Any]) -> int:
    previous = [0] * (len(target) + 1)
    for source_value in source:
        current = [0]
        for index, target_value in enumerate(target, start=1):
            current.append(
                previous[index - 1] + 1
                if source_value == target_value
                else max(previous[index], current[index - 1])
            )
        previous = current
    return previous[-1]


def contains_phrase(text: str, phrase: str) -> bool:
    tokens = normalized_tokens(text)
    phrase_tokens = normalized_tokens(phrase)
    if not phrase_tokens or len(phrase_tokens) > len(tokens):
        return False
    return any(
        tokens[start:start + len(phrase_tokens)] == phrase_tokens
        for start in range(len(tokens) - len(phrase_tokens) + 1)
    )


def active_speakers(turns: list[dict[str, Any]], moment: float) -> set[str]:
    return {
        str(turn["speaker"])
        for turn in turns
        if float(turn["start"]) <= moment < float(turn["end"])
    }


def speaker_mapping(
    reference_turns: list[dict[str, Any]],
    hypothesis_turns: list[dict[str, Any]],
    frame_seconds: float,
) -> dict[str, str]:
    overlap: dict[tuple[str, str], int] = defaultdict(int)
    maximum = max(
        [float(turn["end"]) for turn in reference_turns + hypothesis_turns] or [0]
    )
    frame_count = int(math.ceil(maximum / frame_seconds))
    for frame in range(frame_count):
        moment = (frame + 0.5) * frame_seconds
        for hypothesis in active_speakers(hypothesis_turns, moment):
            for reference in active_speakers(reference_turns, moment):
                overlap[(hypothesis, reference)] += 1
    mapping: dict[str, str] = {}
    used_reference: set[str] = set()
    for (hypothesis, reference), _ in sorted(
        overlap.items(), key=lambda item: (-item[1], item[0][0], item[0][1])
    ):
        if hypothesis not in mapping and reference not in used_reference:
            mapping[hypothesis] = reference
            used_reference.add(reference)
    return mapping


def diarization_counts(
    reference_turns: list[dict[str, Any]],
    hypothesis_turns: list[dict[str, Any]],
    frame_seconds: float = 0.01,
) -> tuple[int, int]:
    if not reference_turns:
        return 0, 0
    mapping = speaker_mapping(reference_turns, hypothesis_turns, frame_seconds)
    maximum = max(
        [float(turn["end"]) for turn in reference_turns + hypothesis_turns] or [0]
    )
    frame_count = int(math.ceil(maximum / frame_seconds))
    errors = 0
    reference_assignments = 0
    for frame in range(frame_count):
        moment = (frame + 0.5) * frame_seconds
        reference = active_speakers(reference_turns, moment)
        hypothesis = {
            mapping.get(speaker, f"unmapped:{speaker}")
            for speaker in active_speakers(hypothesis_turns, moment)
        }
        reference_assignments += len(reference)
        errors += len(reference.symmetric_difference(hypothesis))
    return errors, reference_assignments


def sequence_score(reference: list[str], hypothesis: list[str]) -> tuple[int, int]:
    normalized_reference = [str(value).strip().lower() for value in reference if str(value).strip()]
    normalized_hypothesis = [str(value).strip().lower() for value in hypothesis if str(value).strip()]
    denominator = max(1, len(normalized_reference))
    return edit_distance(normalized_reference, normalized_hypothesis), denominator


def case_counts(reference: dict[str, Any], hypothesis: dict[str, Any]) -> dict[str, float]:
    reference_text = str(reference.get("reference", ""))
    hypothesis_text = str(hypothesis.get("hypothesis", ""))
    reference_tokens = normalized_tokens(reference_text)
    hypothesis_tokens = normalized_tokens(hypothesis_text)
    reference_devanagari = devanagari_characters(reference_text)
    hypothesis_devanagari = devanagari_characters(hypothesis_text)
    terms = [str(value) for value in reference.get("domain_terms", [])]
    language_edits, language_count = sequence_score(
        list(reference.get("languages", [])),
        list(hypothesis.get("languages", [])),
    )
    reference_turns = list(reference.get("speaker_turns", []))
    hypothesis_turns = list(hypothesis.get("segments", []))
    diarization_errors, diarization_reference = diarization_counts(
        reference_turns, hypothesis_turns
    )
    reference_speakers = {str(value["speaker"]) for value in reference_turns}
    hypothesis_speakers = {str(value["speaker"]) for value in hypothesis_turns}
    return {
        "cases": 1,
        "word_edits": edit_distance(reference_tokens, hypothesis_tokens),
        "reference_words": len(reference_tokens),
        "devanagari_edits": edit_distance(reference_devanagari, hypothesis_devanagari),
        "reference_devanagari": len(reference_devanagari),
        "recognized_terms": sum(contains_phrase(hypothesis_text, term) for term in terms),
        "reference_terms": len(terms),
        "dropped_tokens": max(0, len(reference_tokens) - lcs_length(reference_tokens, hypothesis_tokens)),
        "language_edits": language_edits,
        "reference_language_events": language_count,
        "speaker_count_error": abs(len(reference_speakers) - len(hypothesis_speakers)),
        "speaker_cases": int(bool(reference_turns)),
        "diarization_errors": diarization_errors,
        "diarization_reference": diarization_reference,
        "latency_total_ms": float(hypothesis.get("latency_ms", 0)),
    }


def merge_counts(values: Iterable[dict[str, float]]) -> dict[str, float]:
    output: dict[str, float] = defaultdict(float)
    for value in values:
        for key, count in value.items():
            output[key] += count
    return dict(output)


def safe_rate(numerator: float, denominator: float) -> float | None:
    return numerator / denominator if denominator > 0 else None


def percentile(values: Iterable[float], fraction: float) -> float | None:
    ordered = sorted(value for value in values if math.isfinite(value) and value >= 0)
    if not ordered:
        return None
    rank = max(1, math.ceil(min(max(fraction, 0), 1) * len(ordered)))
    return ordered[rank - 1]


def report_from_counts(counts: dict[str, float]) -> dict[str, Any]:
    cases = counts.get("cases", 0)
    language_error = safe_rate(
        counts.get("language_edits", 0), counts.get("reference_language_events", 0)
    )
    return {
        "cases": int(cases),
        "wer": safe_rate(counts.get("word_edits", 0), counts.get("reference_words", 0)),
        "devanagari_cer": safe_rate(
            counts.get("devanagari_edits", 0), counts.get("reference_devanagari", 0)
        ),
        "domain_term_recall": safe_rate(
            counts.get("recognized_terms", 0), counts.get("reference_terms", 0)
        ),
        "dropped_span_rate": safe_rate(
            counts.get("dropped_tokens", 0), counts.get("reference_words", 0)
        ),
        "language_sequence_accuracy": None if language_error is None else max(0, 1 - language_error),
        "mean_speaker_count_error": safe_rate(
            counts.get("speaker_count_error", 0), counts.get("speaker_cases", 0)
        ),
        "diarization_error_rate": safe_rate(
            counts.get("diarization_errors", 0), counts.get("diarization_reference", 0)
        ),
    }


def report_for_cases(
    cases: list[tuple[dict[str, float], dict[str, Any]]]
) -> dict[str, Any]:
    report = report_from_counts(merge_counts(counts for counts, _ in cases))
    latencies = [
        float(hypothesis["latency_ms"])
        for _, hypothesis in cases
        if isinstance(hypothesis.get("latency_ms"), (int, float))
    ]
    warm_latencies = [
        float(hypothesis["latency_ms"])
        for _, hypothesis in cases
        if isinstance(hypothesis.get("latency_ms"), (int, float))
        and not bool(hypothesis.get("cold_start", False))
    ]
    case_count = len(cases)
    empty_count = sum(
        not str(hypothesis.get("hypothesis", "")).strip()
        for _, hypothesis in cases
    )
    report.update({
        "mean_latency_ms": safe_rate(sum(latencies), len(latencies)),
        "latency_p50_ms": percentile(latencies, 0.50),
        "latency_p95_ms": percentile(latencies, 0.95),
        "warm_latency_p50_ms": percentile(warm_latencies, 0.50),
        "warm_latency_p95_ms": percentile(warm_latencies, 0.95),
        "transcription_failures": sum(
            bool(str(hypothesis.get("error", "")).strip())
            for _, hypothesis in cases
        ),
        "empty_hypothesis_rate": safe_rate(empty_count, case_count),
    })
    return report


def build_report(
    references: list[dict[str, Any]],
    hypotheses: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    case_results: list[tuple[str, dict[str, float], dict[str, Any]]] = []
    for reference in references:
        hypothesis = hypotheses.get(str(reference["id"]), {"id": reference["id"]})
        case_results.append((
            str(reference.get("condition", "unspecified")),
            case_counts(reference, hypothesis),
            hypothesis,
        ))

    grouped: dict[str, list[tuple[dict[str, float], dict[str, Any]]]] = defaultdict(list)
    for condition, counts, hypothesis in case_results:
        grouped[condition].append((counts, hypothesis))
    return {
        "schema_version": 2,
        "overall": report_for_cases([
            (counts, hypothesis) for _, counts, hypothesis in case_results
        ]),
        "conditions": {
            condition: report_for_cases(values)
            for condition, values in sorted(grouped.items())
        },
        "missing_hypotheses": [
            reference["id"] for reference in references
            if str(reference["id"]) not in hypotheses
        ],
    }


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--hypotheses", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--max-wer", type=float)
    parser.add_argument("--max-devanagari-cer", type=float)
    parser.add_argument("--max-diarization-error", type=float)
    parser.add_argument("--max-dropped-span-rate", type=float)
    parser.add_argument("--max-empty-hypothesis-rate", type=float)
    parser.add_argument("--max-warm-p95-ms", type=float)
    parser.add_argument("--min-language-sequence-accuracy", type=float)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    references = read_jsonl(arguments.manifest)
    hypotheses = {str(row["id"]): row for row in read_jsonl(arguments.hypotheses)}
    report = build_report(references, hypotheses)
    rendered = json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True)
    if arguments.output:
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        arguments.output.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)

    gates = [
        (arguments.max_wer, report["overall"]["wer"], lambda actual, limit: actual <= limit),
        (arguments.max_devanagari_cer, report["overall"]["devanagari_cer"], lambda actual, limit: actual <= limit),
        (arguments.max_diarization_error, report["overall"]["diarization_error_rate"], lambda actual, limit: actual <= limit),
        (arguments.max_dropped_span_rate, report["overall"]["dropped_span_rate"], lambda actual, limit: actual <= limit),
        (arguments.max_empty_hypothesis_rate, report["overall"]["empty_hypothesis_rate"], lambda actual, limit: actual <= limit),
        (arguments.max_warm_p95_ms, report["overall"]["warm_latency_p95_ms"], lambda actual, limit: actual <= limit),
        (arguments.min_language_sequence_accuracy, report["overall"]["language_sequence_accuracy"], lambda actual, limit: actual >= limit),
    ]
    return 2 if any(limit is not None and (actual is None or not check(actual, limit)) for limit, actual, check in gates) else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"voice-eval-error: {error}", file=sys.stderr)
        raise SystemExit(1)
