# Robust Multilingual Audio and Evaluation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make OpenLoop measurably more reliable for muffled/noisy Hindi–English speech, language changes across long recordings, and multi-speaker meetings, with a reproducible corpus-based evaluation workflow.

**Architecture:** Keep one canonical 16 kHz conditioned signal for both Whisper decoding and SpeakerKit alignment so timestamps remain comparable. Preserve Whisper's timestamped, diarized meeting timeline as the canonical evidence and use Qwen as a bounded recognition witness. Add rolling transcript context and low-energy boundaries to Qwen windows. Evaluate the shipped pipeline by condition and capability rather than hiding failures inside one average.

**Tech Stack:** Swift 6.2, AVFoundation, WhisperKit large-v3, Qwen3-ASR, SpeakerKit/Pyannote, Swift Testing, Python 3 standard library, official Common Voice/IndicVoices/DNS-Challenge/VoxConverse corpora.

---

### Task 1: Lock the audio-conditioning and canonical-timeline contracts

**Files:**
- Modify: `Tests/OpenLoopAppTests/SpeechAudioConditionerTests.swift`
- Modify: `Tests/OpenLoopAppTests/AccuracyFirstTranscriberTests.swift`
- Modify: `Tests/OpenLoopAppTests/LocalMeetingTranscriberTests.swift`

- [ ] **Step 1: Add a degraded-speech conditioner test**

Create deterministic speech plus low-frequency hum and assert that conditioning stays finite, keeps sample count/timing unchanged, reduces DC/low-frequency energy, and does not erase the speech band.

- [ ] **Step 2: Add a speaker-timeline fusion test**

Build a speaker-labelled Whisper output and a speakerless Qwen output, then assert the accuracy wrapper returns the Whisper IDs, timestamps, and speaker labels while retaining fusion evidence.

- [ ] **Step 3: Add a conditioned-array decoding-options test**

Assert automatic Whisper decoding enables VAD chunking, timestamps, language detection, and non-translation transcription.

- [ ] **Step 4: Run the focused tests and record the expected local toolchain limitation**

Run:

```bash
swift test --filter 'SpeechAudioConditionerTests|AccuracyFirstTranscriberTests|LocalMeetingTranscriberTests'
```

Expected locally: the repository-wide test build may stop at `no such module 'Testing'` under Command Line Tools. CI with full Xcode is authoritative; `swift build --target OpenLoopApp` must still compile locally.

### Task 2: Condition every Whisper path and keep diarization on the same signal

**Files:**
- Modify: `Sources/OpenLoopApp/Meetings/LocalMeetingTranscriber.swift`
- Modify: `Sources/OpenLoopApp/Voice/SpeechAudioConditioner.swift`

- [ ] **Step 1: Load and condition audio once per Whisper request**

At the beginning of `transcribe`, load the 16 kHz float array, reset the conditioner, and retain the conditioned array for every short, long, automatic, and forced-language branch.

- [ ] **Step 2: Decode the conditioned array instead of reopening the raw file**

Replace the file-only fallback with an array decoder using:

```swift
try await pipeline.transcribe(
    audioArray: audio,
    decodeOptions: options,
    callback: callback
)
```

Set `chunkingStrategy: .vad` in `decodingOptions` so long recordings split at speech-aware boundaries.

- [ ] **Step 3: Diarize the identical conditioned samples**

Change the diarization boundary to receive `[Float]` and pass that array to SpeakerKit. This keeps the recognizer and speaker model on the same sample clock while leaving the durable source file untouched.

- [ ] **Step 4: Add conservative presence recovery**

Extend `SpeechAudioConditioner` with a small, bounded high-frequency presence term after the existing high-pass stage. Keep the blend deterministic, maintain exact sample count, soft-limit at `0.98`, and reset its state with the existing filter state.

- [ ] **Step 5: Compile the native target**

Run:

```bash
swift build --target OpenLoopApp
```

Expected: `Build of target: 'OpenLoopApp' complete!`.

### Task 3: Preserve language continuity across Qwen windows

**Files:**
- Modify: `Sources/OpenLoopApp/Voice/LongFormAudioSegmenter.swift`
- Modify: `Sources/OpenLoopApp/Meetings/QwenMeetingTranscriber.swift`
- Modify: `Tests/OpenLoopAppTests/LongFormAudioSegmenterTests.swift`
- Modify: `Tests/OpenLoopAppTests/QwenMeetingTranscriberTests.swift`

- [ ] **Step 1: Add a low-energy-boundary regression test**

Construct continuous speech with a quiet valley near the maximum window duration and assert the segmenter cuts at the valley, covers each sample exactly once, and never exceeds the configured duration.

- [ ] **Step 2: Select quiet boundaries instead of fixed cuts**

When a speech range exceeds the maximum window size, search the final bounded portion of the window for the lowest 30 ms RMS frame, prefer the latest point on ties, and use that as the next boundary.

- [ ] **Step 3: Add rolling context tests**

Assert later Qwen calls receive bounded vocabulary plus the tail of the prior stable transcript with an explicit `do not repeat` label, while the first call receives vocabulary only.

- [ ] **Step 4: Feed prior stable text into each later Qwen window**

Build each request context from the existing personal vocabulary and at most the last 48 whitespace-delimited words of accepted transcript. Do not force a language; preserve automatic code switching.

- [ ] **Step 5: Compile the native target**

Run `swift build --target OpenLoopApp` and expect a successful target build.

### Task 4: Preserve speaker turns through accuracy fusion

**Files:**
- Modify: `Sources/OpenLoopApp/Voice/AccuracyFirstTranscriber.swift`
- Modify: `Sources/OpenLoopApp/App/OpenLoopApp.swift`
- Modify: `Tests/OpenLoopAppTests/AccuracyFirstTranscriberTests.swift`

- [ ] **Step 1: Make Whisper the canonical meeting timeline**

Wire `AccuracyFirstTranscriber(primary: whisperTranscriber, witness: qwenTranscriber)` for meeting imports and recordings. Whisper owns word timestamps and SpeakerKit labels; Qwen remains the independent local witness.

- [ ] **Step 2: Reject unsafe text replacement across mismatched time spans**

Only allow witness text to replace canonical text when the two evidence spans have sufficient temporal coverage. Otherwise preserve the timestamped primary text and expose disagreement for review.

- [ ] **Step 3: Assert speaker labels survive selected-text replacement**

Cover both exact agreement and domain-term correction. The returned segment must retain its canonical UUID, start/end, and speaker.

- [ ] **Step 4: Compile and run CI-facing tests**

Run `swift build --target OpenLoopApp`; push only after the target compiles and test sources are committed.

### Task 5: Add a reproducible voice-corpus benchmark

**Files:**
- Create: `Evaluation/voice/README.md`
- Create: `Evaluation/voice/manifest.example.jsonl`
- Create: `Evaluation/voice/corpora.json`
- Create: `Scripts/evals/voice_quality_eval.py`
- Create: `Scripts/evals/bootstrap_voice_corpora.sh`
- Modify: `.gitignore`
- Create: `Tests/Fixtures/voice-eval/hypotheses.example.jsonl`

- [ ] **Step 1: Define one line per immutable audio case**

Each manifest row contains `id`, `audio`, `reference`, `languages`, `condition`, `domain_terms`, and optional `speaker_turns` with `speaker`, `start`, and `end`.

- [ ] **Step 2: Implement the standard-library evaluator**

Read references and hypotheses, then emit JSON containing overall and per-condition WER, Devanagari CER, domain-term recall, dropped-span rate, language-sequence accuracy, speaker-count error, and frame-based diarization error for cases with reference turns. Exit nonzero only when explicit gate arguments are exceeded.

- [ ] **Step 3: Add corpus provenance and license boundaries**

Record official URLs and intended slices for Mozilla Common Voice English/Hindi, AI4Bharat IndicVoices conversational Hindi, Google FLEURS Hindi/English, Microsoft DNS Challenge noise/room impulse responses, and VoxConverse diarization. Keep downloaded audio under ignored `.eval-data/`; never commit third-party audio.

- [ ] **Step 4: Add a safe bootstrap script**

The default `metadata` profile clones only official manifests/tools. Optional `--kaggle <owner/dataset>` uses the installed Kaggle CLI after the user has accepted that dataset's terms. Large audio downloads require an explicit profile.

- [ ] **Step 5: Test the evaluator fixture**

Run:

```bash
python3 Scripts/evals/voice_quality_eval.py \
  --manifest Evaluation/voice/manifest.example.jsonl \
  --hypotheses Tests/Fixtures/voice-eval/hypotheses.example.jsonl
```

Expected: valid JSON with exact-case WER `0`, mixed-language metrics present, and speaker DER present for the diarized fixture.

### Task 6: Document user-supplied evaluation evidence and ship the increment

**Files:**
- Modify: `docs/VOICE_PLATFORM.md`
- Modify: `CHANGELOG.md`
- Modify: `Resources/Info.plist`

- [ ] **Step 1: Document the private-corpus workflow**

Explain how to place recordings under `.eval-data/private/`, create literal ground truth without polishing, annotate language order and speaker turns, run the app, export hypotheses, and compare candidate versions without uploading private audio.

- [ ] **Step 2: State quality gates without a best-in-class claim**

Require condition-level results and regression deltas. A commercial claim remains blocked until the private real-world set and a controlled competitor baseline both pass.

- [ ] **Step 3: Prepare the next patch release**

Bump the patch/build version, update the changelog, build the app and website, package a DMG, install without launching, push, tag, and wait for CI/release evidence.

- [ ] **Step 4: Verify before handoff**

Run fresh native build, evaluator fixture, website build, release verification, installed plist/signature checks, and GitHub CI/release status. Report any environment limitation explicitly.
