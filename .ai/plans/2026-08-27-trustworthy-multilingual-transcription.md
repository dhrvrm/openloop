# Trustworthy Multilingual Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the misleading compressed-model/failing-witness path with a high-quality local transcription path that preserves short language switches and reports incomplete cross-checking instead of silently claiming accuracy.

**Architecture:** Official whisper.cpp full `large-v3` becomes the canonical final recognizer after both compressed and full WhisperKit failed the retained code-switch gate. Its token timestamps are aligned with SpeakerKit turns and fingerprints; Qwen small remains disposable partial feedback. Fusion still marks every requested-but-missing witness span for review and never calls a primary-only result cross-checked.

**Tech Stack:** Swift 6.2, Swift Package Manager, WhisperKit/Core ML, speech-swift Qwen3-ASR/MLX, SpeakerKit, Swift Testing, headless `--voice-eval` runner.

---

## Evidence and acceptance criteria

The retained 27.17-second AAC recording is non-empty, unclipped, and quiet but usable (peak -18.3 dBFS, RMS -36.3 dBFS). The shipped app produced `en + pt`, omitted the Hindi span, and emitted phrases such as “I am a man and I'm curious as not” and “job you will download.” Every stored fusion span was `primaryOnly` because Qwen downloaded to `~/Library/Caches/Models/models/aufklarer/...` while loading from an empty OpenLoop directory.

An independent full `large-v3` decode recovered continuous content:

```text
I am a man. The accuracy is not coming.
जो भी बोलता हूँ वो समझ नहीं आता है।
And the transcription is not getting there.
I think there is no continuity in there, and the voice clarity is okay.
The mic is really good. If I give this recording to OpenAI, that will work,
and somehow we are not able to achieve that.
```

The first clause remains a human-confirmation point; tests must not claim word-error-rate perfection until the user confirms the reference. The implementation is acceptable for this increment when the app's headless decoder preserves the Hindi sentence, does not label it Portuguese, covers the full speech timeline, and exposes any failed secondary engine.

Execution evidence rejected full WhisperKit after Task 1 because it still returned `en + pt` and deleted the Hindi sentence. The implementation therefore advanced to official whisper.cpp; `docs/VOICE_QUALITY.md` records the comparison and final commands.

## File map

- Modify `Sources/OpenLoopApp/Meetings/LocalMeetingTranscriber.swift`: declare the canonical full-quality Whisper model and expose deterministic model choice to diagnostics/evaluation.
- Modify `Sources/OpenLoopApp/Meetings/QwenMeetingTranscriber.swift`: resolve a Hub-style repository directory below the app-owned model root and use it consistently for download, load, and diagnostics.
- Modify `Sources/OpenLoopApp/Voice/AccuracyFirstTranscriber.swift`: turn a requested-but-failed witness into reviewable missing evidence.
- Modify `Sources/ADHDCore/TranscriptFusion.swift`: allow fusion to distinguish “secondary was not requested” from “secondary was required but unavailable.”
- Modify `Sources/OpenLoopApp/Evaluation/VoiceEvaluationRunner.swift`: accept an explicit Whisper model variant for repeatable quality comparisons.
- Modify `Tests/OpenLoopAppTests/LocalMeetingTranscriberTests.swift`: lock the full-quality default and multilingual decoding defaults.
- Modify `Tests/OpenLoopAppTests/QwenMeetingTranscriberTests.swift`: lock Hub-style cache resolution.
- Modify `Tests/ADHDCoreTests/TranscriptFusionTests.swift`: lock missing-secondary review semantics.
- Modify `Tests/OpenLoopAppTests/AccuracyFirstTranscriberTests.swift`: lock witness-failure visibility.
- Modify `docs/voice-quality.md`: record the local eval command, confirmed-reference requirement, and multilingual/speaker test matrix.

### Task 1: Select the actual full-quality Whisper model

- [ ] **Step 1: Write the failing model-selection test**

Add to `Tests/OpenLoopAppTests/LocalMeetingTranscriberTests.swift`:

```swift
@Test func accuracyWhisperUsesTheUncompressedLargeV3Variant() {
    #expect(WhisperKitMeetingTranscriber.defaultModelIdentifier
        == "large-v3-v20240930")
    #expect(!WhisperKitMeetingTranscriber.defaultModelIdentifier.contains("626MB"))
}
```

- [ ] **Step 2: Run the focused test and confirm it fails**

Run:

```bash
scripts/test.sh --filter accuracyWhisperUsesTheUncompressedLargeV3Variant
```

Expected: compile failure because `defaultModelIdentifier` is not defined.

- [ ] **Step 3: Implement the full-quality default**

In `WhisperKitMeetingTranscriber` add:

```swift
static let defaultModelIdentifier = "large-v3-v20240930"
```

and use it as the initializer default. Keep download-on-first-use and the existing app-owned marker path so the old 626 MB model is not mistaken for the new variant.

- [ ] **Step 4: Run the focused test**

Run `scripts/test.sh --filter accuracyWhisperUsesTheUncompressedLargeV3Variant`.

Expected: one passing test.

### Task 2: Make Qwen load the model it downloads

- [ ] **Step 1: Write failing cache-resolution tests**

Add tests that require:

```swift
let root = URL(fileURLWithPath: "/tmp/OpenLoop/Qwen", isDirectory: true)
let resolved = QwenMeetingTranscriber.repositoryDirectory(
    modelID: "aufklarer/Qwen3-ASR-1.7B-MLX-8bit",
    below: root
)
#expect(resolved.path == "/tmp/OpenLoop/Qwen/models/aufklarer/Qwen3-ASR-1.7B-MLX-8bit")
```

Also verify that a malformed model identifier cannot escape the supplied root.

- [ ] **Step 2: Run the focused test and confirm it fails**

Run `scripts/test.sh --filter QwenMeetingTranscriberTests`.

Expected: compile failure because `repositoryDirectory` is not defined.

- [ ] **Step 3: Implement deterministic Hub-style resolution**

Split the model ID on `/`, retain safe non-empty path components, and append `models/<organization>/<model>` below `modelStorageURL`. Pass that resolved URL to `Qwen3ASRModel.fromPretrained`, inspect its `model.safetensors` in diagnostics, and report the resolved model name without claiming “Whisper fallback” when fallback is disabled.

- [ ] **Step 4: Run the focused Qwen tests**

Run `scripts/test.sh --filter QwenMeetingTranscriberTests`.

Expected: all Qwen unit tests pass without loading a real model.

### Task 3: Stop silent accuracy degradation

- [ ] **Step 1: Write failing fusion and orchestration tests**

Add a `secondaryWasRequested` parameter to the fusion test and require:

```swift
let result = policy.fuse(
    primary: [primary],
    secondary: [],
    secondaryWasRequested: true
)
#expect(result.spans[0].resolution == .reviewRequired)
#expect(result.spans[0].reasons.contains(.secondaryEvidenceMissing))
```

Add an `AccuracyFirstTranscriber` test whose witness throws and require the returned span to be review-required, while retaining the primary words and speaker timeline.

- [ ] **Step 2: Run the focused tests and confirm failure**

Run:

```bash
scripts/test.sh --filter 'TranscriptFusionTests|AccuracyFirstTranscriberTests'
```

Expected: the existing code returns `primaryAccepted`/`primaryOnly`.

- [ ] **Step 3: Implement explicit witness availability semantics**

Extend `TranscriptFusionPolicy.fuse` with `secondaryWasRequested: Bool = false`. When no matching secondary exists and the flag is true, set `resolution` to `.reviewRequired` and append `.secondaryEvidenceMissing` even when text heuristics alone did not request escalation. Pass `true` from both the witness-success and witness-failure branches of `AccuracyFirstTranscriber`; pass `false` only when the orchestrator intentionally skipped the witness.

- [ ] **Step 4: Run focused fusion tests**

Run `scripts/test.sh --filter 'TranscriptFusionTests|AccuracyFirstTranscriberTests'`.

Expected: all focused tests pass.

### Task 4: Make headless comparisons reproducible

- [ ] **Step 1: Write a failing argument-parsing test**

In `Tests/OpenLoopAppTests/VoiceEvaluationRunnerTests.swift`, parse:

```text
--voice-eval --manifest corpus.jsonl --output results.jsonl --engine whisper
--whisper-model large-v3-v20240930
```

and require the parsed model ID to equal `large-v3-v20240930`.

- [ ] **Step 2: Add the evaluator option**

Store an optional `whisperModelIdentifier` in `VoiceEvaluationCommand`, parse `--whisper-model`, and pass it to `WhisperKitMeetingTranscriber`; otherwise use `defaultModelIdentifier`.

- [ ] **Step 3: Run evaluator tests**

Run `scripts/test.sh --filter VoiceEvaluationRunnerTests`.

Expected: all evaluator tests pass.

### Task 5: Decode the retained clip without launching the GUI

- [ ] **Step 1: Build the release executable**

Run `swift build -c release --product OpenLoopADHD` through the repository build script environment.

- [ ] **Step 2: Run the headless full-model evaluation**

Use the ignored local manifest under `.artifacts/audit-latest`; do not commit the private audio:

```bash
.build/release/OpenLoopADHD --voice-eval \
  --manifest .artifacts/audit-latest/manifest.jsonl \
  --output .artifacts/audit-latest/results/whisperkit-full.jsonl \
  --engine whisper \
  --whisper-model large-v3-v20240930 \
  --data-directory .artifacts/audit-latest/data-full
```

Expected: the Hindi span is present in Devanagari, the language summary contains `hi` rather than `pt`, and speech coverage has no multi-second hole.

- [ ] **Step 3: Compare outputs by time span**

Record the stored app output, compressed WhisperKit output, Qwen output, official full large-v3 output, and new full WhisperKit output in `docs/voice-quality.md`. Do not report WER until the reference text is user-confirmed.

### Task 6: Package the repair without opening the app

- [ ] **Step 1: Update version and release notes after the headless gate passes**

Increment the patch version/build, describe the full-quality download size and first-run behavior, and state that the audio remains local.

- [ ] **Step 2: Run only the required release checks**

Run focused transcription tests, one release build, and the retained headless evaluation. Do not launch the GUI.

- [ ] **Step 3: Build and install the DMG/app**

Use the existing release scripts, replace `/Applications/OpenLoop ADHD.app` without launching it, create the versioned DMG, tag the commit, push the branch/main integration selected by the user, and attach the DMG to the GitHub release.

## Self-review

- The plan covers the proven cache-path defect, the compressed-primary defect, multilingual continuity, failure visibility, repeatable headless evaluation, and non-GUI packaging.
- Speaker identity remains owned by the canonical Whisper/SpeakerKit timeline; language boundaries do not create speaker identities.
- Punjabi and Spanish are covered by Whisper large-v3's multilingual tokenizer, but sellable quality still requires recorded code-switch and speaker-overlap corpus cases for those languages.
- No private recording is committed, no cloud upload occurs, and no manual language prompt is required.
- “Perfect” is not claimed: low-confidence or missing cross-check evidence becomes visible instead of being silently rewritten as certainty.
