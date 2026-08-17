# Advanced Local Voice Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Evolve the working `Command-Shift-R` on-device transcription flow into a provider-neutral, voice-activity-aware, correction-learning capture framework with reproducible quality metrics and encrypted personal vocabulary.

**Architecture:** `ADHDCore` owns provider-independent correction, vocabulary, and benchmark values plus a `VoiceLearningLoop`; repositories persist corrections with backward-compatible encrypted snapshots. `OpenLoopApp` owns the microphone/Speech adapter, audio-level normalization, capture state, and panel. The Apple provider receives ranked vocabulary phrases before each session and emits normalized audio activity without retaining raw buffers. Typed capture stays independent and every new subsystem has a focused test seam.

**Tech Stack:** Swift 6.2, Swift Package Manager, Swift Testing, SwiftUI, AppKit, AVFoundation/AVAudioEngine, Apple Speech, CryptoKit AES-GCM, Security Keychain Services.

---

## Constraints

- Preserve the visible Increment 3 workspace, `Command-Shift-Space` typed capture, `Command-Shift-R` voice toggle, contextual resurfacing, focus, Return, migration, and encrypted vault behavior.
- Recognition remains on-device-only. Provider contracts may allow later local adapters such as whisper.cpp, but no network provider, download flow, or placeholder provider is added now.
- Do not retain or write microphone audio. The accepted privacy behavior is ephemeral audio into durable encrypted text; recovery preserves the latest editable transcript, not raw buffers.
- Request permissions only after explicit voice activation. Typed capture must work regardless of microphone, speech authorization, recognizer availability, or provider failure.
- Audio levels are descriptive UI feedback, not stored productivity or emotion signals. Do not infer affect, attention, urgency, or identity from voice.
- Correction learning records only a normalized recognized/final text pair after the final transcript is successfully captured. It never rewrites prior captures.
- Vocabulary phrases are derived deterministically from actual corrections, capped at 100, ordered by correction frequency, latest evidence, then lexical tie. No model-generated vocabulary.
- Benchmark metrics are provider-neutral: exact word error rate, first-partial latency, final latency, and separate general/name/technical categories. Missing corpus data produces an explicit empty report, not a fabricated score.
- Continue with focused test cases while building. Do not run exhaustive verification loops unless the user asks.
- Do not create or invoke a `designer` agent. Do not add formal `SUBSYSTEM.md` files.

## File map

- `Sources/ADHDCore/VoiceLearning.swift`: correction value, deterministic vocabulary projection, learning loop, and typed errors.
- `Sources/ADHDCore/VoiceBenchmark.swift`: token normalization, Levenshtein word error rate, sample categories, and aggregate report.
- `Sources/ADHDCore/Ports.swift`: compatible correction persistence contract.
- `Sources/LocalStore/JSONFileThoughtRepository.swift`: development correction persistence.
- `Sources/VaultStore/EncryptedThoughtRepository.swift`: encrypted correction persistence and legacy decoding.
- `Sources/OpenLoopApp/VoiceTranscriptionController.swift`: provider configuration, activity normalization, transcript/correction state, and Apple adapter.
- `Sources/OpenLoopApp/VoiceCaptureWindowController.swift`: responsive activity meter and correction-aware transcript binding.
- `Sources/OpenLoopApp/OpenLoopApp.swift`: production learning-loop wiring and focused benchmark diagnostic.
- `Tests/ADHDCoreTests/VoiceLearningTests.swift`: correction/vocabulary/learning tests.
- `Tests/ADHDCoreTests/VoiceBenchmarkTests.swift`: exact metric tests.
- `Tests/LocalStoreTests/JSONFileThoughtRepositoryTests.swift`: correction restart/legacy tests.
- `Tests/VaultStoreTests/EncryptedThoughtRepositoryTests.swift`: encrypted correction restart/plaintext tests.
- `Tests/OpenLoopAppTests/VoiceTranscriptionControllerTests.swift`: provider config, activity, editing, save, and failure tests.
- `README.md`, `docs/DECISIONS.md`: delivered voice behavior and provider-selection decision.

### Task 1: Define correction learning and deterministic personal vocabulary

**Files:**
- Create: `Sources/ADHDCore/VoiceLearning.swift`
- Create: `Tests/ADHDCoreTests/VoiceLearningTests.swift`
- Modify: `Sources/ADHDCore/Ports.swift`

- [ ] **Step 1: Write failing correction normalization tests**

Test that `TranscriptionCorrection(recognized:corrected:createdAt:)` trims outer whitespace, rejects empty/equal text, preserves the exact corrected phrase, and exposes stable token differences. Use this intended interface:

```swift
let correction = try TranscriptionCorrection(
    recognized: "open x code",
    corrected: "Open Xcode",
    createdAt: Date(timeIntervalSince1970: 10)
)
#expect(correction.recognized == "open x code")
#expect(correction.corrected == "Open Xcode")
#expect(correction.learnedPhrases == ["Open Xcode", "Xcode"])
```

- [ ] **Step 2: Run the focused failure**

Run `Scripts/test.sh --filter VoiceLearningTests`.

Expected: compilation fails because `TranscriptionCorrection` does not exist.

- [ ] **Step 3: Write failing vocabulary projection tests**

Verify `PersonalVocabulary(corrections:).phrases(limit:)` de-duplicates case-insensitively, ranks repeated corrections first, then most recent evidence, then localized lexical order, and never returns more than 100 phrases. Original-only words must not become hints.

- [ ] **Step 4: Implement domain values and compatible repository requirements**

Add these exact repository requirements with safe compatibility defaults:

```swift
func save(transcriptionCorrection: TranscriptionCorrection) async throws
func transcriptionCorrections() async throws -> [TranscriptionCorrection]
```

The save default throws `ThoughtRepositoryCompatibilityError.voiceLearningUnsupported`; the read default returns `[]`. Implement `TranscriptionCorrection`, `PersonalVocabulary`, `VoiceLearningError`, and `VoiceLearningLoop.record(recognized:corrected:at:)` / `vocabulary(limit:)`.

- [ ] **Step 5: Run focused tests and commit**

Run `Scripts/test.sh --filter VoiceLearningTests`.

Commit: `feat: learn deterministic vocabulary from voice corrections`.

### Task 2: Add provider-neutral voice quality metrics

**Files:**
- Create: `Sources/ADHDCore/VoiceBenchmark.swift`
- Create: `Tests/ADHDCoreTests/VoiceBenchmarkTests.swift`

- [ ] **Step 1: Write failing word-error-rate tests**

Cover exact match (`0`), one substitution, insertion, deletion, case/punctuation normalization, and empty reference/hypothesis behavior. The public calculation is:

```swift
let metric = VoiceBenchmarkMetric(reference: "Open Xcode", hypothesis: "open code")
#expect(metric.referenceWordCount == 2)
#expect(metric.editCount == 1)
#expect(metric.wordErrorRate == 0.5)
```

- [ ] **Step 2: Write failing aggregate report tests**

Define `VoiceBenchmarkCategory.general`, `.name`, and `.technical`; `VoiceBenchmarkSample` carries reference, hypothesis, first-partial milliseconds, and final milliseconds. Verify `VoiceBenchmarkReport(samples:)` exposes micro-averaged WER, nearest-rank p95 latencies, and separate per-category WER. An empty report has `nil` metrics and zero samples.

- [ ] **Step 3: Implement deterministic metrics**

Tokenize with Unicode letter/number sequences and lowercase using `en_US_POSIX`. Compute edit distance with two integer rows, not a full matrix. Aggregate edit/reference counts before division so long samples have proportional weight. Reuse the existing nearest-rank p95 convention.

- [ ] **Step 4: Run focused tests and commit**

Run `Scripts/test.sh --filter VoiceBenchmarkTests`.

Commit: `feat: measure provider-neutral voice quality`.

### Task 3: Persist corrections in both repositories without exposing plaintext

**Files:**
- Modify: `Sources/LocalStore/JSONFileThoughtRepository.swift`
- Modify: `Sources/VaultStore/EncryptedThoughtRepository.swift`
- Modify: `Tests/LocalStoreTests/JSONFileThoughtRepositoryTests.swift`
- Modify: `Tests/VaultStoreTests/EncryptedThoughtRepositoryTests.swift`

- [ ] **Step 1: Write failing development repository tests**

Save two corrections with equal dates and deterministic UUIDs, reopen, and verify date/UUID ordering. Save a snapshot without `transcriptionCorrections` and verify it still opens with an empty correction list.

- [ ] **Step 2: Write failing encrypted repository tests**

Save a distinctive recognized/corrected pair, reopen, compare exactly, and scan every file in the vault directory to prove neither phrase appears as plaintext. Reuse the existing schema-1 fixture to prove missing correction fields decode as empty.

- [ ] **Step 3: Add backward-compatible snapshot fields**

Both snapshots add:

```swift
var transcriptionCorrections: [UUID: TranscriptionCorrection] = [:]
```

Custom decoders use `decodeIfPresent(...) ?? [:]`. Local saves use one locked update; vault saves use one AES-GCM snapshot update. Stable reads sort by `createdAt` then UUID. Include corrections in vault `empty()` and import-emptiness guards without changing authenticated data.

- [ ] **Step 4: Run focused repository tests and commit**

Run `Scripts/test.sh --filter 'transcriptionCorrection|legacySnapshotWithoutClarifications|schemaOneVaultWithoutFocusSessions'`.

Commit: `feat: persist encrypted voice correction evidence`.

### Task 4: Generalize the live provider contract and expose voice activity

**Files:**
- Modify: `Sources/OpenLoopApp/VoiceTranscriptionController.swift`
- Modify: `Tests/OpenLoopAppTests/VoiceTranscriptionControllerTests.swift`

- [ ] **Step 1: Extend the fake-provider tests first**

Replace the current `start(onTranscript:onFailure:)` seam with:

```swift
struct SpeechProviderConfiguration: Equatable {
    let contextualPhrases: [String]
    let requiresOnDeviceRecognition: Bool
}

func start(
    configuration: SpeechProviderConfiguration,
    onTranscript: @escaping @MainActor @Sendable (String, Bool) -> Void,
    onAudioLevel: @escaping @MainActor @Sendable (Double) -> Void,
    onFailure: @escaping @MainActor @Sendable (String) -> Void
) throws
```

Verify the controller loads vocabulary before start, always passes `requiresOnDeviceRecognition == true`, clamps level events into `0...1`, and resets the published level to zero on stop/cancel/failure.

- [ ] **Step 2: Test audio normalization separately**

`AudioLevelNormalizer.normalized(rms:)` maps silence/invalid values to `0`, `0.001` near the floor, and `1.0` to `1`, using `20 * log10(rms)` clamped from `-60...0 dB`. `VoiceActivityDetector` uses a `0.12` threshold and exposes `hasDetectedSpeech` without storing samples.

- [ ] **Step 3: Implement the generalized controller contract**

Inject `vocabulary: @MainActor () async -> [String]`. Publish `audioLevel` and `hasDetectedSpeech`. Keep all existing toggle, one-minute, retry, and empty-transcript behavior. Provider failure preserves editable text and zeros activity.

- [ ] **Step 4: Update the Apple provider**

Set `request.contextualStrings` to at most 100 ranked phrases and keep `requiresOnDeviceRecognition = true`. In the audio tap, calculate RMS from the first float channel without retaining the buffer, normalize it, and deliver it to the main actor. Continue appending the same buffer directly to Speech.

- [ ] **Step 5: Run focused app tests and commit**

Run `Scripts/test.sh --filter VoiceTranscriptionControllerTests`.

Commit: `feat: expose provider-neutral voice activity`.

### Task 5: Record user edits as correction evidence and improve the panel

**Files:**
- Modify: `Sources/OpenLoopApp/VoiceTranscriptionController.swift`
- Modify: `Sources/OpenLoopApp/VoiceCaptureWindowController.swift`
- Modify: `Sources/OpenLoopApp/OpenLoopApp.swift`
- Modify: `Tests/OpenLoopAppTests/VoiceTranscriptionControllerTests.swift`

- [ ] **Step 1: Write failing editing/learning tests**

Verify provider partials update both recognized and editable text until the user edits; `editTranscript(_:)` changes only the editable text; later provider partials do not overwrite a user edit; successful save calls `recordCorrection` once only when normalized recognized/final text differs; failed save records nothing; retry records once after success.

- [ ] **Step 2: Implement correction-aware controller state**

Inject:

```swift
recordCorrection: @MainActor (String, String, Date) async -> Void
```

Track `recognizedTranscript`, `transcriptWasEdited`, and session start. After `save(value)` succeeds, record the correction before clearing state. Never block capture success if correction persistence fails.

- [ ] **Step 3: Wire `VoiceLearningLoop` in production**

Construct the loop from the encrypted repository. The vocabulary closure calls `vocabulary(limit: 100)` and falls back to `[]` on error. The correction closure calls `record(...)` and leaves the already-saved capture untouched on failure.

- [ ] **Step 4: Render activity and explicit learning copy**

Replace direct `$controller.transcript` mutation with a `Binding` whose setter calls `editTranscript`. Add five native activity bars driven by `audioLevel`, accessibility value `Voice detected` / `Listening`, and quiet copy `Edits improve names and technical words on this Mac`. Do not display an accuracy score in the capture panel.

- [ ] **Step 5: Run focused app tests and commit**

Run `Scripts/test.sh --filter VoiceTranscriptionControllerTests`.

Commit: `feat: learn from edited voice captures`.

### Task 6: Add a reproducible benchmark fixture path and document Increment 4

**Files:**
- Modify: `Sources/OpenLoopApp/OpenLoopApp.swift`
- Create: `Tests/Fixtures/voice-benchmark.json`
- Modify: `README.md`
- Modify: `docs/DECISIONS.md`
- Modify: `.ai/plans/2026-08-17-advanced-local-voice.md`

- [ ] **Step 1: Add a focused packaged benchmark diagnostic**

`--voice-benchmark <fixture.json>` decodes `[VoiceBenchmarkSample]`, prints stable lines for sample count, overall WER, first-partial p95, final p95, and each category, and exits nonzero only for malformed fixtures. It evaluates supplied provider output; it does not claim the fixture is a live microphone benchmark.

- [ ] **Step 2: Add a deterministic mixed fixture**

Include at least one general phrase, one personal-name phrase, and one technical phrase. Expected values are asserted in `VoiceBenchmarkTests`; distinctive text remains test-only and never enters the user's vault.

- [ ] **Step 3: Document the provider framework and privacy boundary**

README explains activity feedback, edit-based vocabulary, benchmark invocation, and that raw audio remains ephemeral. Add a decision recording deterministic correction evidence, provider-neutral metrics, and Apple Speech as the selected on-device adapter pending personal-corpus evidence.

- [ ] **Step 4: Run only focused Increment 4 tests**

Run:

```bash
Scripts/test.sh --filter 'VoiceLearningTests|VoiceBenchmarkTests|VoiceTranscriptionControllerTests|transcriptionCorrection'
```

Do not run the exhaustive Increment 3 gate unless the user asks.

- [ ] **Step 5: Commit the focused Increment 4 handoff**

Commit: `feat: complete advanced local voice framework`.

Expected focused evidence: correction/vocabulary tests pass; WER and latency reports are exact; both repositories reopen correction history and the vault scan finds no correction plaintext; the Apple adapter receives ranked contextual phrases and emits bounded activity; edited successful transcripts record one correction; typed capture remains structurally independent; and the fixture diagnostic reports category metrics without presenting them as live-provider results.
