# Advanced Meeting Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Apple Speech as OpenLoop's primary voice path with a visible, local-first multilingual meeting pipeline that accepts audio files or microphone recordings, reports every meaningful stage, and preserves searchable transcripts without recurring Keychain or Speech Recognition prompts.

**Architecture:** `ADHDCore` owns provider-neutral meeting jobs, timed transcript segments, and durable transcript records. `OpenLoopApp` owns audio import/recording, a `WhisperKit` adapter, model lifecycle, orchestration, and SwiftUI status surfaces. Imported or recorded audio is copied into an app-owned staging directory before asynchronous work; the local model produces timestamped multilingual text, and successful transcripts enter the encrypted OpenLoop vault. Apple Speech remains compiled only as a legacy test seam until its old controller can be removed safely. A future FluidAudio adapter can merge local diarization with WhisperKit segments without changing the product model.

**Tech Stack:** Swift 6.2, Swift Package Manager, Swift Testing, SwiftUI, AppKit, AVFoundation, WhisperKit/Core ML, CryptoKit AES-GCM, existing encrypted vault.

---

## Constraints

- Local processing is the default. No meeting audio is uploaded and no API key is required.
- Importing a file must request neither microphone nor Speech Recognition permission. Recording requests microphone access only after the user presses Record.
- The UI must always show the current state: waiting for model, downloading with progress, preparing audio, transcribing with progress, saving, ready, cancelled, or failed with a retry action.
- A first model download is explicit, cancellable where the SDK permits, and cached for later use. Never describe a model download as audio upload.
- Optimize for multilingual meeting accuracy on Apple silicon. Default to WhisperKit's recommended model selection; expose a high-accuracy model preference after the basic path is stable.
- Imported/recorded audio is retained only while needed for retry, with clear local-only copy. Successful jobs remove staging audio after the encrypted transcript is saved unless the user chooses to keep it in a later increment.
- Transcript results include source name, creation time, detected language when available, timed segments, duration, and model identifier. Speaker labels are optional until the local diarization adapter lands; never fabricate them.
- A whole transcript is evidence, not automatically a task. Users explicitly choose excerpts to capture as tasks or memory.
- Fresh ad-hoc development installs generate and use a file-protected local root key without Keychain. Existing legacy vault migration must never occur as a surprise prompt; it must be explicit or preserve the already-migrated local key.
- Ad-hoc signing cannot provide stable macOS TCC identity. The implementation removes Speech Recognition permission entirely from the new path and documents that stable Developer ID signing is still required to make microphone permission survive binary replacement.
- Keep the existing four workspace destinations; meeting import/status/results live in Recall and the existing Quick Add composer.
- Run focused tests and one build, not exhaustive verification loops. Do not launch the installed app during automated work.
- Do not create or invoke a `designer` agent. Do not add formal `SUBSYSTEM.md` files.

## File map

- `Package.swift`: add pinned WhisperKit product dependency; stop requiring Speech for production wiring once legacy code allows.
- `Sources/ADHDCore/MeetingTranscription.swift`: durable job, stage, timed segment, transcript record, and provider-neutral errors.
- `Sources/ADHDCore/Ports.swift`: compatible meeting transcript persistence requirements.
- `Sources/LocalStore/JSONFileThoughtRepository.swift`: development transcript persistence.
- `Sources/VaultStore/EncryptedThoughtRepository.swift`: encrypted transcript persistence and legacy defaults.
- `Sources/VaultStore/VaultKeyProvider.swift`: safe local-only root-key provider with no Keychain access.
- `Sources/OpenLoopApp/LocalMeetingTranscriber.swift`: WhisperKit lifecycle, progress mapping, language detection, and timed result conversion.
- `Sources/OpenLoopApp/MeetingTranscriptionController.swift`: app-owned staging, import/record orchestration, durable presentation state, retry/cancel, cleanup.
- `Sources/OpenLoopApp/MeetingAudioRecorder.swift`: microphone-only `.m4a` recording without Apple Speech.
- `Sources/OpenLoopApp/AppModel.swift`: controller observation and product actions.
- `Sources/OpenLoopApp/OpenLoopApp.swift`: production wiring, shortcut/menu routing, and local key selection.
- `Sources/OpenLoopApp/MainWindowController.swift`: Import Audio, Record/Stop, model/job status, transcript result, retry, and capture-excerpt controls.
- `Resources/Info.plist`: remove Speech Recognition usage copy from the new packaged path; update microphone/local model copy.
- `Tests/ADHDCoreTests/MeetingTranscriptionTests.swift`: domain invariant tests.
- `Tests/VaultStoreTests/EncryptedThoughtRepositoryTests.swift`: encrypted transcript restart/plaintext tests.
- `Tests/OpenLoopAppTests/MeetingTranscriptionControllerTests.swift`: import, progress, success, retry, cancellation, cleanup, and no-key behavior.
- `README.md`, `docs/DECISIONS.md`: local-first model, first-run download, privacy, permission, and signing decisions.

### Task 1: Define provider-neutral meeting transcript values

**Files:**
- Create: `Sources/ADHDCore/MeetingTranscription.swift`
- Create: `Tests/ADHDCoreTests/MeetingTranscriptionTests.swift`
- Modify: `Sources/ADHDCore/Ports.swift`

- [x] Write failing tests for ordered timed segments, progress clamping, terminal job states, transcript duration, and empty-text rejection.
- [x] Implement `MeetingTranscriptionStage`, `MeetingTranscriptionProgress`, `TranscriptSegment`, `MeetingTranscript`, and typed errors as `Codable`, `Equatable`, `Sendable`, and identifiable where appropriate.
- [x] Add backward-compatible repository requirements for saving, listing, and deleting meeting transcripts; default reads return empty and unsupported writes throw a typed compatibility error.
- [x] Run `Scripts/test.sh --filter MeetingTranscriptionTests`.

### Task 2: Persist transcripts in the encrypted vault

**Files:**
- Modify: `Sources/LocalStore/JSONFileThoughtRepository.swift`
- Modify: `Sources/VaultStore/EncryptedThoughtRepository.swift`
- Modify: `Tests/LocalStoreTests/JSONFileThoughtRepositoryTests.swift`
- Modify: `Tests/VaultStoreTests/EncryptedThoughtRepositoryTests.swift`

- [x] Write restart and legacy-snapshot tests for local and encrypted repositories.
- [x] Write a vault scan proving distinctive transcript text and segment text never appear in plaintext.
- [x] Add transcript dictionaries with `decodeIfPresent(...) ?? [:]`, stable newest-first reads, and atomic save/delete operations.
- [ ] Include transcript counts/bytes in privacy summaries only where the existing abstraction supports it without schema churn.
- [x] Run focused transcript persistence tests.

### Task 3: Remove automatic Keychain access from local development builds

**Files:**
- Modify: `Sources/VaultStore/VaultKeyProvider.swift`
- Modify: `Sources/OpenLoopApp/OpenLoopApp.swift`
- Modify: `Tests/VaultStoreTests/V1PrivacyTests.swift`

- [x] Write tests that a `LocalFileVaultKeyProvider` creates a 32-byte random key, applies mode `0600`, reopens the same key, rejects symlinks/invalid files, and never calls a fallback provider.
- [x] Implement the provider with `SecRandomCopyBytes`, atomic complete-file-protection writes, and strict file validation.
- [x] For local builds, use the existing `root-key.local` directly or create it only when no vault exists. If a legacy vault exists without a local key, surface an explicit migration error instead of touching Keychain automatically.
- [x] Keep release builds on Keychain pending stable Developer ID signing.
- [x] Run focused vault-key tests.

### Task 4: Integrate WhisperKit behind a testable local transcriber

**Files:**
- Modify: `Package.swift`
- Create: `Sources/OpenLoopApp/LocalMeetingTranscriber.swift`
- Create: `Tests/OpenLoopAppTests/LocalMeetingTranscriberTests.swift`

- [x] Add the current stable `argmax-oss-swift` package pinned from `1.1.0` and depend on the `WhisperKit` product.
- [x] Define a small `MeetingTranscribing` protocol that emits model-download/load/transcription progress and returns provider-neutral segments.
- [x] Wrap WhisperKit configuration with automatic language detection, segment timestamps, app-support model cache, recommended-device model selection, and a high-accuracy model identifier seam.
- [x] Map SDK errors into concise actionable product errors without exposing paths or secrets.
- [x] Use a fake engine in unit tests to prove progress mapping and result conversion; do not download a production model in tests.
- [x] Run focused adapter tests and one compile.

### Task 5: Add permission-free audio import and durable visible jobs

**Files:**
- Create: `Sources/OpenLoopApp/MeetingTranscriptionController.swift`
- Create: `Tests/OpenLoopAppTests/MeetingTranscriptionControllerTests.swift`
- Modify: `Sources/OpenLoopApp/AppModel.swift`

- [x] Write focused tests for supported import, staging copy, progress, success persistence, and successful staging cleanup.
- [x] Implement a main-actor controller with a single active job plus recent completed transcripts; copy imports before the open panel security scope expires.
- [x] Persist finished transcripts through the repository and keep failed audio locally for explicit retry.
- [x] Expose current model name, local/cloud destination, elapsed time, fractional progress, source name, and readable next action.
- [x] Observe the controller from `AppModel` and expose import/retry/cancel/delete/capture actions.
- [x] Run focused controller/model tests.

### Task 6: Route live recording through the same local pipeline

**Files:**
- Create: `Sources/OpenLoopApp/MeetingAudioRecorder.swift`
- Modify: `Sources/OpenLoopApp/MeetingTranscriptionController.swift`
- Modify: `Sources/OpenLoopApp/AppModel.swift`
- Modify: `Sources/OpenLoopApp/OpenLoopApp.swift`
- Modify: `Resources/Info.plist`

- [ ] Write recorder/controller tests around a fake recorder: explicit start, elapsed/audio-level feedback, stop-to-job handoff, cancel cleanup, denied microphone, and interruption.
- [x] Implement AVAudioRecorder `.m4a` capture with metering and microphone-only authorization.
- [x] Change Command-Shift-R, status-menu Record, and Quick Add Record to toggle this recorder; do not instantiate `OnDeviceSpeechTranscriber` in production.
- [x] Remove `NSSpeechRecognitionUsageDescription` and update microphone copy to explain local meeting transcription and temporary audio.
- [x] Keep typed capture independent and functional when local model setup or microphone access fails.
- [x] Run focused recording/controller tests.

### Task 7: Ship the meeting UI with continuous feedback

**Files:**
- Modify: `Sources/OpenLoopApp/MainWindowController.swift`
- Modify: `Tests/OpenLoopAppTests/MainWindowControllerTests.swift`

- [x] Add `Import audio...` next to Record in Quick Add and a prominent local-processing label.
- [x] Add a compact active-job panel to Now and a Meeting Transcripts section to Recall, with progress bar, stage text, elapsed time, source, model, local-only badge, cancel/retry, and clear error recovery.
- [x] Render completed timed segments with text selection, detected language, duration, model, and explicit capture action.
- [x] Show first-run local-model copy and that audio stays on the Mac.
- [ ] Add stable accessibility labels and focused UI-structure tests.
- [x] Run a focused UI compile.

### Task 8: Document, package, and install closed

**Files:**
- Modify: `README.md`
- Modify: `docs/DECISIONS.md`
- Modify: `.ai/plans/2026-08-18-advanced-meeting-transcription.md`

- [x] Document WhisperKit as default local multilingual ASR and SpeakerKit as the local diarization adapter.
- [x] Document why file import needs no TCC permission and why stable signing—not repeated prompting—is the remaining microphone-permission fix.
- [ ] Run only focused meeting/key tests and one release build; do not launch the app.
- [ ] Replace `/Applications/OpenLoop ADHD.app` once, preserving the old build in Trash, and leave the new app closed.
- [ ] Record implementation evidence and remaining diarization work in this plan.
