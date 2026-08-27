#!/usr/bin/env python3
"""Create conservative, literal labels from independent ASR hypotheses."""

from __future__ import annotations

import argparse
import json
import sys
import unicodedata
from pathlib import Path
from typing import Any


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


def index_rows(rows: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    indexed: dict[str, dict[str, Any]] = {}
    for row in rows:
        case_id = str(row["id"])
        if case_id in indexed:
            raise ValueError(f"duplicate hypothesis id: {case_id}")
        indexed[case_id] = row
    return indexed


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


def edit_distance(left: list[str], right: list[str]) -> int:
    previous = list(range(len(right) + 1))
    for left_index, left_value in enumerate(left, start=1):
        current = [left_index]
        for right_index, right_value in enumerate(right, start=1):
            current.append(min(
                previous[right_index] + 1,
                current[right_index - 1] + 1,
                previous[right_index - 1] + (left_value != right_value),
            ))
        previous = current
    return previous[-1]


def transcript_distance(left: str, right: str) -> float:
    left_tokens = normalized_tokens(left)
    right_tokens = normalized_tokens(right)
    return edit_distance(left_tokens, right_tokens) / max(
        1, len(left_tokens), len(right_tokens)
    )


def language_sequence(row: dict[str, Any]) -> tuple[str, ...]:
    sequence: list[str] = []
    for raw_value in row.get("languages", []):
        value = str(raw_value).strip().lower()
        if value and (not sequence or sequence[-1] != value):
            sequence.append(value)
    return tuple(sequence)


def medoid(witnesses: list[tuple[str, dict[str, Any]]]) -> tuple[str, dict[str, Any]]:
    def total_distance(candidate: tuple[str, dict[str, Any]]) -> tuple[float, str]:
        name, row = candidate
        text = str(row.get("hypothesis", ""))
        return (
            sum(
                transcript_distance(text, str(other.get("hypothesis", "")))
                for _, other in witnesses
            ),
            name,
        )

    return min(witnesses, key=total_distance)


def build_consensus(
    manifest_rows: list[dict[str, Any]],
    sources: dict[str, dict[str, dict[str, Any]]],
    minimum_agreement: float = 0.90,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    labels: list[dict[str, Any]] = []
    reviews: list[dict[str, Any]] = []

    for manifest in manifest_rows:
        case_id = str(manifest["id"])
        submitted = [(name, rows.get(case_id)) for name, rows in sorted(sources.items())]
        witness_payload = {
            name: row if row is not None else {"id": case_id, "error": "missing hypothesis"}
            for name, row in submitted
        }

        if manifest.get("split") == "release-test":
            reviews.append({
                "id": case_id,
                "split": "release-test",
                "eligible_for_distillation": False,
                "reasons": ["held-out-release-test"],
                "witnesses": witness_payload,
            })
            continue

        successful = [
            (name, row)
            for name, row in submitted
            if row is not None
            and not row.get("error")
            and str(row.get("hypothesis", "")).strip()
        ]
        reasons: list[str] = []
        if any(
            row is None or row.get("error") or not str(row.get("hypothesis", "")).strip()
            for _, row in submitted
        ):
            reasons.append("failed-witness")
        if len(successful) < 2:
            reasons.append("insufficient-witnesses")

        pairwise_agreement = 0.0
        if len(successful) >= 2:
            agreements = [
                1 - transcript_distance(
                    str(left.get("hypothesis", "")),
                    str(right.get("hypothesis", "")),
                )
                for left_index, (_, left) in enumerate(successful)
                for _, right in successful[left_index + 1:]
            ]
            pairwise_agreement = min(agreements)
            if pairwise_agreement < minimum_agreement:
                reasons.append("text-disagreement")
            if len({language_sequence(row) for _, row in successful}) != 1:
                reasons.append("language-sequence-disagreement")

        if reasons:
            reviews.append({
                "id": case_id,
                "split": manifest.get("split"),
                "eligible_for_distillation": False,
                "minimum_pairwise_agreement": pairwise_agreement,
                "reasons": reasons,
                "witnesses": witness_payload,
            })
            continue

        selected_name, selected = medoid(successful)
        labels.append({
            "id": case_id,
            "split": manifest.get("split"),
            "text": str(selected["hypothesis"]),
            "languages": list(language_sequence(selected)),
            "segments": selected.get("segments", []),
            "chosen_source": selected_name,
            "label_authority": "teacher-consensus",
            "minimum_pairwise_agreement": pairwise_agreement,
            "eligible_for_distillation": True,
            "witnesses": witness_payload,
        })

    return labels, reviews


def parse_source(value: str) -> tuple[str, Path]:
    name, separator, raw_path = value.partition("=")
    if not separator or not name.strip() or not raw_path.strip():
        raise argparse.ArgumentTypeError("expected NAME=PATH")
    return name.strip(), Path(raw_path)


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--hypothesis", action="append", type=parse_source, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--review-output", type=Path, required=True)
    parser.add_argument("--minimum-agreement", type=float, default=0.90)
    arguments = parser.parse_args(argv)

    try:
        manifest = read_jsonl(arguments.manifest)
        sources = {
            name: index_rows(read_jsonl(path)) for name, path in arguments.hypothesis
        }
        labels, reviews = build_consensus(
            manifest, sources, minimum_agreement=arguments.minimum_agreement,
        )
        write_jsonl(arguments.output, labels)
        write_jsonl(arguments.review_output, reviews)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        return 2

    print(json.dumps({
        "consensus_labels": len(labels),
        "review_required": len(reviews),
        "minimum_agreement": arguments.minimum_agreement,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
