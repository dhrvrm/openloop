#!/usr/bin/env python3
"""Materialize a deterministic, human-labelled FLEURS evaluation slice."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any


LANGUAGES = {"en_us": "en", "hi_in": "hi"}


def manifest_row(
    config: str,
    sample: dict[str, Any],
    relative_audio: str,
    digest: str,
) -> dict[str, Any]:
    language = LANGUAGES[config]
    return {
        "id": f"fleurs-{config}-{sample['id']}",
        "audio": relative_audio,
        "audio_sha256": digest,
        "split": "release-test",
        "reference": str(sample["transcription"]).strip(),
        "reference_status": "human-confirmed",
        "languages": [language],
        "condition": "fleurs-clean",
        "domain_terms": [],
        "speaker_ids": [],
        "corpus_id": "fleurs-en-us-hi-in",
        "source": "google/fleurs",
    }


def materialize(output_root: Path, split: str, per_language: int) -> list[dict[str, Any]]:
    from datasets import Audio, load_dataset

    output_root.mkdir(parents=True, exist_ok=True)
    rows: list[dict[str, Any]] = []
    for config in LANGUAGES:
        stream = load_dataset("google/fleurs", config, split=split, streaming=True)
        stream = stream.cast_column("audio", Audio(decode=False))
        language_directory = output_root / config
        language_directory.mkdir(parents=True, exist_ok=True)
        for index, sample in enumerate(stream):
            if index >= per_language:
                break
            audio = sample["audio"]
            payload = audio.get("bytes")
            if not isinstance(payload, bytes) or not payload:
                raise ValueError(f"{config}/{sample['id']}: encoded audio bytes are missing")
            filename = f"{sample['id']}.wav"
            audio_path = language_directory / filename
            audio_path.write_bytes(payload)
            digest = hashlib.sha256(payload).hexdigest()
            rows.append(manifest_row(
                config,
                sample,
                str(audio_path.resolve()),
                digest,
            ))
    return rows


def write_jsonl(output: Path, rows: list[dict[str, Any]]) -> None:
    with output.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--split", choices=["validation", "test"], default="test")
    parser.add_argument("--per-language", type=int, default=3)
    arguments = parser.parse_args(argv)
    if arguments.per_language < 1:
        parser.error("--per-language must be positive")

    try:
        rows = materialize(arguments.output_root, arguments.split, arguments.per_language)
        manifest = arguments.output_root / "manifest.jsonl"
        write_jsonl(manifest, rows)
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 2
    print(json.dumps({"cases": len(rows), "manifest": str(manifest.resolve())}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
