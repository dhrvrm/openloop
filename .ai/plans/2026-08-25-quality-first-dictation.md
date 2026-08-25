# Quality-first dictation implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give global dictation a stronger asynchronous final-quality path and a compact, persistent macOS HUD while preserving the meeting pipeline's timestamps and speaker evidence.

**Architecture:** The recording controller selects a transcriber from an explicit recording purpose captured when recording begins. A warm Qwen3-ASR 0.6B model provides live partials; global dictation uses Qwen3-ASR 1.7B as its canonical final recognizer with Whisper as a witness; meeting imports and recordings keep Whisper as the canonical timed transcript with Qwen 1.7B as a witness. A pure HUD projection turns app state into stable presentation data, and the SwiftUI panel renders that projection as a compact morphing capsule/card.

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, Qwen3ASR, WhisperKit, Swift Testing.

---

### Task 1: Route recording purpose to the correct final recognizer

**Files:**
- Modify: `Sources/OpenLoopApp/Meetings/MeetingTranscriptionController.swift`
- Modify: `Sources/OpenLoopApp/App/AppModel.swift`
- Test: `Tests/OpenLoopAppTests/MeetingTranscriptionControllerTests.swift`

- [x] **Step 1: Write failing purpose-routing tests**

Add a recording-purpose enum and tests that construct a controller with distinct meeting and dictation spies. Assert `toggleRecording(purpose: .dictation)` calls only the dictation recognizer after stop, while import and `.meeting` recording call only the meeting recognizer.

- [ ] **Step 2: Run the focused tests and confirm the new assertions fail**

Run:

```bash
xcodebuild test -scheme OpenLoopADHD-Package -destination 'platform=macOS' -only-testing:OpenLoopAppTests/MeetingTranscriptionControllerTests
```

Expected: failure because purpose selection and the second transcriber do not exist.

- [x] **Step 3: Implement explicit purpose selection**

Add:

```swift
enum AudioCapturePurpose: Equatable, Sendable {
    case meeting
    case dictation
}
```

Store `activeCapturePurpose` when recording starts, select `dictationTranscriber ?? transcriber` when finalization begins, and pass `.dictation` from `AppModel.toggleSystemDictation()` and `.meeting` from ordinary recording.

- [x] **Step 4: Run the focused tests**

Run the command from Step 2. Expected: all controller tests pass.

### Task 2: Make the strongest local ASR the dictation primary

**Files:**
- Modify: `Sources/OpenLoopApp/Meetings/QwenMeetingTranscriber.swift`
- Modify: `Sources/OpenLoopApp/App/OpenLoopApp.swift`
- Test: `Tests/OpenLoopAppTests/QwenMeetingTranscriberTests.swift`
- Test: `Tests/OpenLoopAppTests/AccuracyFirstTranscriberTests.swift`

- [x] **Step 1: Add a failing default-model test**

Expose a stable accuracy-first default identifier and assert it resolves to `ASRModelSize.large.defaultModelId`, while tests can still inject a small model identifier and fake loader.

- [ ] **Step 2: Run the Qwen and ensemble tests and confirm the assertion fails**

```bash
xcodebuild test -scheme OpenLoopADHD-Package -destination 'platform=macOS' -only-testing:OpenLoopAppTests/QwenMeetingTranscriberTests -only-testing:OpenLoopAppTests/AccuracyFirstTranscriberTests
```

- [x] **Step 3: Compose separate quality policies**

Construct one shared 1.7B final Qwen actor and one 0.6B streaming actor. Use:

```swift
let meetingTranscriber = AccuracyFirstTranscriber(
    primary: whisperTranscriber,
    witness: qwenTranscriber,
    expectedDomainTerms: vocabulary
)
let dictationTranscriber = AccuracyFirstTranscriber(
    primary: qwenTranscriber,
    witness: whisperTranscriber,
    expectedDomainTerms: vocabulary
)
```

Inject both into the controller. This makes dictation text quality independent from meeting diarization without loading duplicate Qwen models.

- [x] **Step 4: Run the focused tests**

Run the command from Step 2. Expected: pass.

### Task 3: Turn the global HUD into the shortcut interaction

**Files:**
- Modify: `Sources/OpenLoopApp/UI/VoiceCaptureWindowController.swift`
- Test: `Tests/OpenLoopAppTests/V1ReliabilityTests.swift`

- [x] **Step 1: Write failing pure projection tests**

Define `VoiceHUDContent` with title, detail, shortcut hint, tone, visibility of meter/transcript/actions, and compact/expanded layout. Test recording, post-stop accuracy refinement, success, confirmation, and failure.

- [ ] **Step 2: Run the HUD tests and confirm they fail**

```bash
xcodebuild test -scheme OpenLoopADHD-Package -destination 'platform=macOS' -only-testing:OpenLoopAppTests/V1ReliabilityTests
```

- [x] **Step 3: Implement the compact morphing HUD**

Render a top-center non-activating panel with a 20-point continuous corner radius, material-backed neutral surface, red recording state, symmetric dB waveform, live partial text, and explicit `Listening`, `Improving accuracy`, `Inserted`, and failure states. Keep cancel/stop actions keyboard accessible and size the window from its fitting content after each state change.

- [x] **Step 4: Run the HUD tests**

Run the command from Step 2. Expected: pass.

### Task 4: Bounded integration verification

**Files:**
- Modify: `.ai/plans/2026-08-25-quality-first-dictation.md`

- [x] **Step 1: Run only affected suites together**

```bash
xcodebuild test -scheme OpenLoopADHD-Package -destination 'platform=macOS' \
  -only-testing:OpenLoopAppTests/MeetingTranscriptionControllerTests \
  -only-testing:OpenLoopAppTests/QwenMeetingTranscriberTests \
  -only-testing:OpenLoopAppTests/AccuracyFirstTranscriberTests \
  -only-testing:OpenLoopAppTests/V1ReliabilityTests
```

Expected: all selected tests pass.

- [x] **Step 2: Build the release configuration without launching the app**

```bash
xcodebuild build -scheme OpenLoopADHD-Package -configuration Release -destination 'platform=macOS'
```

Expected: `BUILD SUCCEEDED`.

- [x] **Step 3: Record evidence and commit**

Mark completed checkboxes, record the exact selected-test and build results below the task list, then commit the focused change as `feat: add quality-first global dictation`.

## Verification evidence

- `swift build --target OpenLoopApp` — passed on 2026-08-25; the changed app target compiled.
- `swift build -c release --target OpenLoopApp` — passed on 2026-08-25; production compilation completed in 17.99 seconds after the final engine split.
- `git diff --check` — passed on 2026-08-25.
- Focused `xcodebuild test` — unavailable because `xcode-select` points to Command Line Tools rather than Xcode.
- Focused `swift test` — unavailable because this Command Line Tools installation does not provide the Swift `Testing` module. The regression tests are committed for Xcode/CI execution; they are not represented as passing locally.
- GitHub Actions CI run `32811316603` — passed on 2026-08-25. The native Xcode build and complete native test target passed in 4 minutes 20 seconds; the website build passed in 16 seconds.
