#!/usr/bin/env python3
"""Reject voice-corpus leakage before decoding, distillation, or evaluation."""

from __future__ import annotations

import argparse
import json
import string
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


VALID_SPLITS = {"distill-train", "development", "release-test"}
HEX = set(string.hexdigits)


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for number, line in enumerate(handle, start=1):
            value = line.strip()
            if not value or value.startswith("#"):
                continue
            row = json.loads(value)
            if not isinstance(row, dict):
                raise ValueError(f"{path}:{number}: expected a JSON object")
            rows.append(row)
    return rows


def validate_rows(
    rows: list[dict[str, Any]],
    base_directory: Path,
    require_audio: bool = False,
) -> tuple[dict[str, Any], list[str]]:
    errors: list[str] = []
    seen_ids: set[str] = set()
    hashes: dict[str, set[str]] = defaultdict(set)
    speakers: dict[str, set[str]] = defaultdict(set)
    counts: Counter[str] = Counter()

    for index, row in enumerate(rows, start=1):
        case_id = str(row.get("id", "")).strip() or f"row-{index}"
        if case_id in seen_ids:
            errors.append(f"{case_id}: duplicate id")
        seen_ids.add(case_id)

        split = str(row.get("split", "")).strip()
        if split not in VALID_SPLITS:
            errors.append(f"{case_id}: split must be one of {sorted(VALID_SPLITS)}")
            continue
        counts[split] += 1

        audio = str(row.get("audio", "")).strip()
        if not audio:
            errors.append(f"{case_id}: audio path is required")
        elif require_audio and not (base_directory / audio).resolve().is_file():
            errors.append(f"{case_id}: audio file does not exist: {audio}")

        digest = str(row.get("audio_sha256", "")).strip().lower()
        if len(digest) != 64 or any(character not in HEX for character in digest):
            errors.append(f"{case_id}: audio_sha256 must contain 64 hexadecimal characters")
        else:
            hashes[digest].add(split)

        raw_speakers = row.get("speaker_ids", [])
        if not isinstance(raw_speakers, list):
            errors.append(f"{case_id}: speaker_ids must be a list")
        else:
            for raw_speaker in raw_speakers:
                speaker = str(raw_speaker).strip()
                if not speaker:
                    errors.append(f"{case_id}: speaker_ids cannot contain empty values")
                else:
                    speakers[speaker].add(split)

        if split == "release-test":
            if row.get("reference_status") != "human-confirmed":
                errors.append(
                    f"{case_id}: release-test requires a human-confirmed reference"
                )
            if not str(row.get("reference", "")).strip():
                errors.append(f"{case_id}: release-test requires literal reference text")

    for digest, digest_splits in sorted(hashes.items()):
        if len(digest_splits) > 1:
            errors.append(
                f"audio hash appears across splits {sorted(digest_splits)}: {digest}"
            )
    for speaker, speaker_splits in sorted(speakers.items()):
        if {"distill-train", "release-test"}.issubset(speaker_splits):
            errors.append(
                f"speaker {speaker} appears in distill-train and release-test"
            )

    report = {
        "valid": not errors,
        "rows": len(rows),
        "rows_by_split": dict(sorted(counts.items())),
        "unique_audio_hashes": len(hashes),
        "unique_speakers": len(speakers),
    }
    return report, errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--require-audio", action="store_true")
    arguments = parser.parse_args(argv)

    try:
        rows = read_jsonl(arguments.manifest)
        report, errors = validate_rows(
            rows,
            arguments.manifest.parent,
            require_audio=arguments.require_audio,
        )
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(json.dumps({"valid": False, "errors": [str(error)]}, ensure_ascii=False))
        return 2

    report["errors"] = errors
    print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if not errors else 2


if __name__ == "__main__":
    sys.exit(main())
