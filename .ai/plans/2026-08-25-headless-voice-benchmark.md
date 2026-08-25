# Headless Voice Benchmark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run OpenLoop's production local speech engines over a frozen audio manifest without launching the GUI, then publish accuracy, continuity, failure, and warm-latency evidence.

**Architecture:** A small command boundary intercepts `--voice-eval` before `NSApplication` is created. A focused Swift runner parses immutable references, drives the same Qwen/Whisper/accuracy-first transcribers used by dictation, and writes scorer-compatible JSONL; the Python scorer remains engine-agnostic and adds percentile/failure reporting and release gates.

**Tech Stack:** Swift 6.2, Swift Testing, Qwen3ASR, WhisperKit, Python 3 standard library, GitHub Actions.

---

### Task 1: Specify the exported evidence

**Files:**
- Create: `Tests/OpenLoopAppTests/VoiceEvaluationRunnerTests.swift`
- Create: `Tests/Scripts/test_voice_quality_eval.py`

- [ ] **Step 1: Add Swift tests for script-order language events, scorer-compatible segment export, cold/warm case marking, and nonfatal per-case failures.**
- [ ] **Step 2: Add Python tests proving nearest-rank P50/P95 latency, warm-latency exclusion of the first cold load, empty-output counting, and gate exit behavior.**
- [ ] **Step 3: Run the focused tests and confirm they fail because the runner and metrics do not exist yet.**

### Task 2: Build the no-GUI production-engine runner

**Files:**
- Create: `Sources/OpenLoopApp/Evaluation/VoiceEvaluationRunner.swift`
- Modify: `Sources/OpenLoopApp/App/OpenLoopApp.swift`

- [ ] **Step 1: Define Codable manifest and hypothesis rows with stable JSONL encoding.**
- [ ] **Step 2: Add a Unicode-script language-sequence detector that collapses adjacent English/Hindi runs and leaves unknown-only text unlabelled.**
- [ ] **Step 3: Add a sequential runner accepting an injected `MeetingTranscribing` engine, measuring each complete transcription call, exporting speaker segments, and preserving failures as evidence rows.**
- [ ] **Step 4: Add command parsing for `--voice-eval`, `--manifest`, `--output`, `--engine`, `--language`, and `--data-directory`; construct `dictation`, `meeting`, `qwen`, or `whisper` using the production model cache paths.**
- [ ] **Step 5: Intercept the command before `NSApplication.shared` so benchmark runs never create a window, dock activation, keychain prompt, or app data migration.**

### Task 3: Make quality reports decision-grade

**Files:**
- Modify: `Scripts/evals/voice_quality_eval.py`
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add case latency arrays, nearest-rank P50/P95, separate warm P50/P95, transcription-failure count, and empty-hypothesis rate.**
- [ ] **Step 2: Add `--max-warm-p95-ms`, `--max-empty-hypothesis-rate`, and `--max-dropped-span-rate` gates.**
- [ ] **Step 3: Run Python scorer tests in CI before native compilation.**

### Task 4: Document and verify the operator workflow

**Files:**
- Modify: `Evaluation/voice/README.md`

- [ ] **Step 1: Document the exact headless command, engine meanings, model download behavior, output paths, and a production-style gate command.**
- [ ] **Step 2: Run Python tests, the example scorer, focused native tests where the local toolchain permits them, and `swift build --target OpenLoopApp`; do not launch OpenLoop.**
- [ ] **Step 3: Review the diff for GUI activation, private audio leakage, and unrelated changes, then commit the focused increment.**
