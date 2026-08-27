# Teacher–Student Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reproducible pipeline that uses slow independent recognizers to create reviewable provisional labels, fine-tunes compact candidates only from eligible data, and scores every model against frozen human-confirmed references.

**Architecture:** Corpus policy, teacher consensus, model comparison, and training export remain separate commands connected through JSONL files. The teacher selects an existing literal hypothesis by deterministic medoid agreement; it never rewrites speech. Release-test rows are immutable, human-confirmed, excluded from distillation, and used to score both teacher and student independently.

**Tech Stack:** Python 3 standard library, existing OpenLoop headless voice evaluation JSONL, Kaggle CLI, Hugging Face-compatible JSONL export, Swift application decoders.

---

### Task 1: Enforce corpus partitions before using any audio

**Files:**
- Create: `Scripts/evals/voice_corpus_guard.py`
- Create: `Tests/Scripts/test_voice_corpus_guard.py`
- Modify: `Evaluation/voice/manifest.example.jsonl`

- [ ] **Step 1: Write failing partition tests**

Cover valid `distill-train`, `development`, and `release-test` rows; reject a release row without `reference_status: human-confirmed`, duplicate audio hashes across splits, and release speakers that appear in training.

- [ ] **Step 2: Run the focused test and verify failure**

Run `python3 -m unittest Tests/Scripts/test_voice_corpus_guard.py`.

Expected: import failure because `voice_corpus_guard.py` does not exist.

- [ ] **Step 3: Implement the guard**

The command accepts `--manifest PATH` and `--require-audio`. It emits JSON with row counts by split. It exits `2` with precise row-level errors when:

```python
VALID_SPLITS = {"distill-train", "development", "release-test"}

if split == "release-test" and row.get("reference_status") != "human-confirmed":
    errors.append(f"{case_id}: release-test requires a human-confirmed reference")
```

It also prevents one `audio_sha256` from crossing splits and prevents any `speaker_ids` value from appearing in both `distill-train` and `release-test`.

- [ ] **Step 4: Run the focused test and verify success**

Run `python3 -m unittest Tests/Scripts/test_voice_corpus_guard.py`.

Expected: all tests pass.

- [ ] **Step 5: Commit**

Commit message: `feat: enforce voice corpus partitions`.

### Task 2: Produce conservative teacher consensus labels

**Files:**
- Create: `Scripts/evals/teacher_consensus.py`
- Create: `Tests/Scripts/test_teacher_consensus.py`

- [ ] **Step 1: Write failing consensus tests**

Cover exact agreement, deterministic medoid selection, language-sequence disagreement, insufficient witnesses, and forced exclusion of release-test rows.

- [ ] **Step 2: Run the focused test and verify failure**

Run `python3 -m unittest Tests/Scripts/test_teacher_consensus.py`.

Expected: import failure because `teacher_consensus.py` does not exist.

- [ ] **Step 3: Implement literal medoid selection**

The command accepts repeated `--hypothesis NAME=PATH`, plus `--manifest`, `--output`, and `--review-output`. For each case, calculate normalized token edit similarity and select the submitted transcript with the smallest summed distance:

```python
distance = edit_distance(normalized_tokens(left), normalized_tokens(right))
score = distance / max(1, len(normalized_tokens(left)), len(normalized_tokens(right)))
```

Set `eligible_for_distillation` only when at least two witnesses exist, minimum pairwise agreement is at least `0.90`, normalized language sequences agree, the row is not `release-test`, and no witness reports an error. Disagreements go to the review file with every unmodified witness hypothesis.

- [ ] **Step 4: Run the focused test and verify success**

Run `python3 -m unittest Tests/Scripts/test_teacher_consensus.py`.

Expected: all tests pass.

- [ ] **Step 5: Commit**

Commit message: `feat: add conservative teacher consensus`.

### Task 3: Compare teacher and students against gold, never against each other alone

**Files:**
- Create: `Scripts/evals/compare_voice_models.py`
- Create: `Tests/Scripts/test_compare_voice_models.py`

- [ ] **Step 1: Write a failing comparison test**

Use one human-confirmed reference, a perfect teacher, and an imperfect student. Assert both receive independent WER reports and the student delta is positive.

- [ ] **Step 2: Run the focused test and verify failure**

Run `python3 -m unittest Tests/Scripts/test_compare_voice_models.py`.

Expected: import failure because `compare_voice_models.py` does not exist.

- [ ] **Step 3: Implement multi-model comparison**

Import `build_report` from `voice_quality_eval.py`. Accept repeated `--model NAME=PATH`, require only `release-test` rows by default, and emit:

```json
{
  "reference_authority": "human-confirmed",
  "models": {"teacher": {"overall": {}}, "student": {"overall": {}}},
  "delta_from_best": {"student": {"wer": 0.1}}
}
```

Reject non-human references unless `--allow-development` is explicit.

- [ ] **Step 4: Run the focused test and verify success**

Run `python3 -m unittest Tests/Scripts/test_compare_voice_models.py`.

Expected: all tests pass.

- [ ] **Step 5: Commit**

Commit message: `feat: compare voice models against gold`.

### Task 4: Record Kaggle provenance and safe usage status

**Files:**
- Modify: `Evaluation/voice/corpora.json`
- Modify: `Scripts/evals/bootstrap_voice_corpora.sh`
- Modify: `Evaluation/voice/README.md`
- Create: `Tests/Scripts/test_voice_corpora_catalog.py`

- [ ] **Step 1: Write a failing catalog test**

Require every corpus to declare `usage_status`, `license_evidence`, `allowed_uses`, and `forbidden_uses`. Require Kaggle entries to declare the exact slug and observed dataset version/update timestamp.

- [ ] **Step 2: Run the catalog test and verify failure**

Run `python3 -m unittest Tests/Scripts/test_voice_corpora_catalog.py`.

- [ ] **Step 3: Add audited Kaggle entries**

Record Punjabi Shrutilipi as `pending-license-resolution`; the YouTube-derived language set as `excluded-commercial`; and transcript-free call-center samples as `exploratory-only`. No pending or excluded corpus may be exported for fine-tuning.

- [ ] **Step 4: Make bootstrap policy-aware**

Add `--catalog-only` to download Kaggle metadata/file listings without audio, and require `--allow-status evaluation-approved` before downloading an audio corpus.

- [ ] **Step 5: Run focused catalog tests**

Run `python3 -m unittest Tests/Scripts/test_voice_corpora_catalog.py`.

Expected: all tests pass.

- [ ] **Step 6: Commit**

Commit message: `docs: audit voice corpus provenance`.

### Task 5: Export eligible distillation rows for a compact candidate

**Files:**
- Create: `Scripts/evals/export_distillation_dataset.py`
- Create: `Tests/Scripts/test_export_distillation_dataset.py`
- Modify: `Evaluation/voice/README.md`

- [ ] **Step 1: Write failing export tests**

Assert the exporter includes consensus and human-confirmed training rows, excludes release-test/review-required/pending-license rows, retains language order, and records source provenance.

- [ ] **Step 2: Run the focused test and verify failure**

Run `python3 -m unittest Tests/Scripts/test_export_distillation_dataset.py`.

- [ ] **Step 3: Implement the export**

Emit one JSONL row per training example with `audio`, `text`, `languages`, `source`, `label_authority`, and `audio_sha256`. Keep speaker diarization labels in a separate sidecar because the distribution ASR model does not own speaker identity.

- [ ] **Step 4: Run all evaluation-script tests**

Run `python3 -m unittest discover -s Tests/Scripts -p 'test_*voice*.py'` and the two new teacher/distillation test modules explicitly.

- [ ] **Step 5: Commit**

Commit message: `feat: export trusted distillation data`.

### Task 6: Run the first headless teacher/student comparison

**Files:**
- Create under ignored storage: `.eval-data/manifests/`, `.eval-data/hypotheses/`, `.eval-data/reports/`
- Modify: `docs/VOICE_QUALITY.md`

- [ ] **Step 1: Validate the private manifest**

Run the corpus guard before any decoder.

- [ ] **Step 2: Run independent hypotheses**

Run full Whisper large-v3, the distribution candidate, and any configured cloud teacher against identical audio without launching AppKit.

- [ ] **Step 3: Build teacher consensus only for training/development**

Generate consensus and review JSONL; never generate labels for release-test rows.

- [ ] **Step 4: Score every model against frozen gold**

Produce per-condition WER, Devanagari CER, domain-term recall, language-sequence accuracy, dropped-span rate, diarization error, and latency.

- [ ] **Step 5: Record measured results without a superiority claim**

Document corpus size, unresolved reference words, exclusions, and exact model identifiers. A competitive claim remains blocked until the same frozen audio is scored through the competitor.

