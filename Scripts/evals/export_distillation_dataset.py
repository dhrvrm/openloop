#!/usr/bin/env python3
"""Export only consented, licensed, non-held-out ASR training examples."""

from __future__ import annotations

import argparse
import json
import sys
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


def catalog_index(document: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {str(corpus["id"]): corpus for corpus in document.get("corpora", [])}


def fine_tuning_allowed(corpus: dict[str, Any] | None) -> bool:
    if corpus is None or corpus.get("usage_status") != "evaluation-approved":
        return False
    return any(
        str(value).startswith("fine-tuning")
        for value in corpus.get("allowed_uses", [])
    )


def export_rows(
    manifest_rows: list[dict[str, Any]],
    labels: dict[str, dict[str, Any]],
    catalog: dict[str, dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[dict[str, str]]]:
    exported: list[dict[str, Any]] = []
    excluded: list[dict[str, str]] = []

    for manifest in manifest_rows:
        case_id = str(manifest["id"])
        if manifest.get("split") != "distill-train":
            excluded.append({"id": case_id, "reason": "held-out-split"})
            continue

        is_private = manifest.get("source") == "private"
        if is_private and manifest.get("training_consent") is not True:
            excluded.append({
                "id": case_id, "reason": "private-training-consent-required",
            })
            continue
        corpus_id = str(manifest.get("corpus_id", "")).strip()
        if not is_private and not fine_tuning_allowed(catalog.get(corpus_id)):
            excluded.append({
                "id": case_id, "reason": "corpus-not-approved-for-fine-tuning",
            })
            continue

        human_text = (
            str(manifest.get("reference", "")).strip()
            if manifest.get("reference_status") == "human-confirmed"
            else ""
        )
        label = labels.get(case_id)
        if human_text:
            text = human_text
            languages = list(manifest.get("languages", []))
            authority = "human-confirmed"
        elif label is None:
            excluded.append({"id": case_id, "reason": "missing-teacher-label"})
            continue
        elif label.get("eligible_for_distillation") is not True:
            excluded.append({"id": case_id, "reason": "teacher-review-required"})
            continue
        else:
            text = str(label.get("text", "")).strip()
            languages = list(label.get("languages", manifest.get("languages", [])))
            authority = str(label.get("label_authority", "teacher-consensus"))

        if not text:
            excluded.append({"id": case_id, "reason": "empty-label"})
            continue

        exported.append({
            "id": case_id,
            "audio": str(manifest["audio"]),
            "audio_sha256": str(manifest["audio_sha256"]),
            "text": text,
            "languages": languages,
            "source": "private" if is_private else corpus_id,
            "label_authority": authority,
            "condition": manifest.get("condition", "unspecified"),
        })

    return exported, excluded


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--teacher-labels", type=Path, required=True)
    parser.add_argument("--corpora", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--excluded-output", type=Path, required=True)
    arguments = parser.parse_args(argv)

    try:
        manifest = read_jsonl(arguments.manifest)
        labels = {str(row["id"]): row for row in read_jsonl(arguments.teacher_labels)}
        catalog = catalog_index(json.loads(arguments.corpora.read_text(encoding="utf-8")))
        exported, excluded = export_rows(manifest, labels, catalog)
        write_jsonl(arguments.output, exported)
        write_jsonl(arguments.excluded_output, excluded)
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        return 2

    print(json.dumps({
        "exported": len(exported), "excluded": len(excluded),
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
