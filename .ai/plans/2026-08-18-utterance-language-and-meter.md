# Utterance Language Detection and Live Meter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve Hindi at the end of English-dominant short recordings and make active microphone input unmistakably visible through a red, real-dB recording meter.

**Architecture:** For automatic short recordings, load the bounded audio into memory, derive silence-separated utterance ranges with WhisperKit's energy VAD, transcribe each range independently with automatic language detection, and merge timestamped results with an ordered language summary. Separately, publish `AVAudioRecorder` average-power readings through the recorder, controller, and app model into one reusable SwiftUI meter; longer imports retain the existing bounded-memory pipeline.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation, WhisperKit 1.1, Swift Testing, macOS speech fixture scripts.

---

### Task 1: Specify utterance boundaries and language summaries

**Files:**
- Create: `Sources/OpenLoopApp/UtteranceAudioChunker.swift`
- Create: `Tests/OpenLoopAppTests/UtteranceAudioChunkerTests.swift`
- Modify: `Tests/OpenLoopAppTests/LocalMeetingTranscriberTests.swift`

- [x] **Step 1: Write failing chunker tests**

Create synthetic 16 kHz sample arrays with two voiced regions separated by 800 ms of silence. Assert that the chunker returns two padded, ordered ranges; assert that pauses below 450 ms remain one utterance; and assert that silence returns no ranges.

- [x] **Step 2: Write a failing language-summary test**

Assert `WhisperKitMeetingTranscriber.languageSummary(["en", "en", "hi", "hi"]) == "en + hi"`, while one language returns that language and blank inputs return `nil`.

- [x] **Step 3: Run the focused tests and confirm missing APIs fail compilation**

Run: `Scripts/test.sh --filter 'UtteranceAudioChunkerTests|languageSummary'`

Expected: compilation fails because `UtteranceAudioChunker` and `languageSummary` do not exist.

- [x] **Step 4: Implement the pure chunker and summary**

Use `EnergyVAD(frameLength: 0.05, energyThreshold: 0.005)`, merge active ranges separated by at most 450 ms, discard speech shorter than 350 ms, and apply 150 ms bounded padding. Add order-preserving language de-duplication in `languageSummary`.

- [x] **Step 5: Run the focused tests**

Run: `Scripts/test.sh --filter 'UtteranceAudioChunkerTests|languageSummary'`

Expected: all selected tests pass.

### Task 2: Decode short automatic recordings per utterance

**Files:**
- Modify: `Sources/OpenLoopApp/LocalMeetingTranscriber.swift`
- Modify: `Tests/OpenLoopAppTests/HindiMeetingIntegrationTests.swift`
- Modify: `Scripts/verify-codeswitch.sh`

- [x] **Step 1: Build an English-then-Hindi two-voice fixture**

Generate the English portion with macOS Rishi and the Hindi ending with Lekha, convert both to mono 16 kHz PCM, join them with 800 ms of silence, and require the final result to report both `en` and `hi`, preserve `Dhruv`, and contain Devanagari Hindi.

- [x] **Step 2: Run the fixture against the one-window implementation**

Run: `Scripts/verify-codeswitch.sh`

Expected: failure because the whole short clip exposes only one detected language or romanizes the Hindi ending.

- [x] **Step 3: Add the bounded utterance path**

When `languageCode == nil`, duration is at most 45 seconds, and the chunker finds more than one utterance, call `WhisperKit.transcribe(audioArray:audioArrayOffset:decodeOptions:)` sequentially for each range. Publish accumulated preview text and per-utterance progress, then pass merged results through existing diarization/storage. Forced-language and long-file jobs keep the existing path.

- [x] **Step 4: Aggregate detected languages**

Use the ordered language summary in both normal mapping and diarized mapping so a mixed recording reports `en + hi` rather than only its first language.

- [x] **Step 5: Run multilingual acceptance**

Run: `Scripts/verify-codeswitch.sh && Scripts/verify-hindi.sh`

Expected: the two-voice fixture reports English plus Hindi and retains Devanagari at the end; the Hindi-dominant fixture still passes.

### Task 3: Publish real microphone decibels

**Files:**
- Modify: `Sources/OpenLoopApp/MeetingAudioRecorder.swift`
- Modify: `Sources/OpenLoopApp/MeetingTranscriptionController.swift`
- Modify: `Sources/OpenLoopApp/AppModel.swift`
- Modify: `Tests/OpenLoopAppTests/MeetingTranscriptionControllerTests.swift`

- [x] **Step 1: Write the failing controller propagation test**

Extend `FakeMeetingRecorder` with an optional dB callback. Emit `-23.5` while recording and assert the controller publishes it; stop recording and assert the controller clears it.

- [x] **Step 2: Run the focused test and confirm the missing meter API fails compilation**

Run: `Scripts/test.sh --filter liveRecordingPublishesAndClearsDecibels`

Expected: compilation fails because recorder/controller dB APIs do not exist.

- [x] **Step 3: Meter the real recorder**

Add an optional `onDecibelUpdate` callback to `MeetingAudioRecording`. While `AVAudioRecorder` is active, poll `updateMeters()` every 60 ms on the main run loop, publish clamped `averagePower(forChannel: 0)` values from -60 through 0 dB, and invalidate the timer on stop/cancel/deinit.

- [x] **Step 4: Propagate and clear meter state**

Publish `recordingDecibels` from `MeetingTranscriptionController`, clear it on stop/cancel/failure, and subscribe from `AppModel` alongside the existing job observations.

- [x] **Step 5: Run the controller tests**

Run: `Scripts/test.sh --filter 'liveRecordingPublishesAndClearsDecibels|MeetingTranscriptionControllerTests'`

Expected: all selected tests pass.

### Task 4: Render an unmistakable recording state

**Files:**
- Modify: `Sources/OpenLoopApp/MainWindowController.swift`

- [x] **Step 1: Add `RecordingLevelMeter`**

Create a compact SwiftUI component with a red live dot, `MIC INPUT` label, actual dB-derived vertical bars, and a monospaced numeric dB readout. Use muted inactive bars and accessibility text that reports the measured level.

- [x] **Step 2: Upgrade the active controls**

Make Record a prominent red Stop & transcribe button while active. Show the meter directly below Quick Add controls and inside the meeting job panel; replace the recording-stage 0% progress bar with the meter and elapsed time.

- [x] **Step 3: Compile the native UI**

Run: `Scripts/test.sh --filter 'MeetingTranscriptionControllerTests|TranscriptionContextTests'`

Expected: the SwiftUI target compiles and all selected tests pass.

### Task 5: Package and install build 9 closed

**Files:**
- Modify: `Resources/Info.plist`
- Modify: `README.md`

- [x] **Step 1: Document utterance auto-detection and the real dB meter**

Describe short-recording phrase-level language detection, the `en + hi` summary, and the red meter as real local microphone measurements rather than animation.

- [x] **Step 2: Bump `CFBundleVersion` from 8 to 9**

Set the integer build string to `9`.

- [x] **Step 3: Build and install without launching**

Run `Scripts/build-app.sh`, verify the signature, quit only an idle installed process if necessary, move build 8 to a recoverable Trash backup, copy build 9 to `/Applications/OpenLoop ADHD.app`, and confirm the process stays closed.

- [x] **Step 4: Run the focused final gate and commit**

Run both speech fixtures, chunker/controller/context tests, `git diff --check`, installed build/signature checks, and the closed-process check. Commit with `fix: preserve language switches and meter recording`.

## Self-review

- Spec coverage: real retry failure, utterance-level auto-detection, timestamps, long-file memory behavior, red recording state, real dB visibility, acceptance, packaging, and no-launch installation are covered.
- Placeholder scan: every behavior and command is explicit; no deferred implementation markers remain.
- Type consistency: `UtteranceAudioChunker`, `languageSummary`, `onDecibelUpdate`, and `recordingDecibels` are named consistently across production and tests.
