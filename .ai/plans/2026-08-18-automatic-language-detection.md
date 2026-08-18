# Automatic Language Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make invisible Whisper language detection the default for every new recording and import, while retaining a session-only manual override in Advanced mode.

**Architecture:** `AppModel` owns a non-persisted `.automatic` preference and forwards it to `MeetingTranscriptionController`, which already maps automatic mode to WhisperKit's `language: nil` and `detectLanguage: true`. The main capture and Recall surfaces contain no language controls; Advanced exposes the override and completed transcript rows continue to report the detected language.

**Tech Stack:** Swift 6, SwiftUI, WhisperKit, Swift Testing, zsh release scripts.

---

### Task 1: Lock the automatic-default behavior with tests

**Files:**
- Modify: `Tests/OpenLoopAppTests/MainWindowControllerTests.swift`
- Modify: `Tests/OpenLoopAppTests/MeetingTranscriptionControllerTests.swift`

- [x] **Step 1: Replace the persisted-language test**

Replace `hindiMeetingPreferencePersistsAcrossAppModels` with a test that seeds the old defaults key, verifies a new `AppModel` still starts in `.automatic`, verifies an in-session override can be selected, and verifies a second model returns to `.automatic`.

- [x] **Step 2: Add an automatic-controller assertion**

Exercise the meeting controller without setting a manual preference and assert the transcriber receives `nil` for its language code.

- [x] **Step 3: Run the focused tests and confirm they fail before implementation**

Run: `Scripts/test.sh --filter 'meetingLanguageAlwaysStartsWithAutomaticDetection|automaticLanguageDetectionPassesNoLanguageCodeToWhisper'`

Expected: the model persistence test fails because the previous Hindi choice is restored, or compilation fails after removing the obsolete initializer argument in the test.

### Task 2: Remove language friction from the normal UI

**Files:**
- Modify: `Sources/OpenLoopApp/AppModel.swift`
- Modify: `Sources/OpenLoopApp/MainWindowController.swift`
- Modify: `Sources/OpenLoopApp/AdvancedInspector.swift`

- [x] **Step 1: Make language override session-only**

Delete `meetingLanguageKey` and all `UserDefaults` reads/writes for meeting language. Initialize `meetingLanguagePreference` to `.automatic`; keep `setMeetingLanguagePreference` so Advanced can modify the current session.

- [x] **Step 2: Remove normal-flow language controls**

Delete the picker from Recall and Quick Add, delete the now-unused `MeetingLanguagePicker`, and hide the job language badge when the requested preference is `.automatic`.

- [x] **Step 3: Add the Advanced override**

Replace the read-only Language fact with a menu picker labelled `Language detection`. Explain that Auto detects the spoken language and manual options are temporary overrides. Disable the picker while a job is active.

- [x] **Step 4: Run the focused tests**

Run: `Scripts/test.sh --filter 'meetingLanguageAlwaysStartsWithAutomaticDetection|MeetingTranscriptionControllerTests'`

Expected: all selected tests pass.

### Task 3: Make Hindi acceptance test the default path

**Files:**
- Modify: `Scripts/verify-hindi.sh`
- Modify: `README.md`

- [x] **Step 1: Remove the forced Hindi environment variable**

Run the synthetic Hinglish acceptance fixture without `OPENLOOP_LANGUAGE_CODE` so Whisper must detect Hindi itself.

- [x] **Step 2: Document automatic detection**

State that recording/import needs no language setup, detected language remains visible on completed transcripts, and the Advanced override lasts only for the current app session.

- [x] **Step 3: Run the Hindi acceptance test**

Run: `Scripts/verify-hindi.sh`

Expected: detected language is `hi`, at least 20 Devanagari scalars are produced, and the transcript contains the expected meeting/project terms.

### Task 4: Package and install build 7 without launching it

**Files:**
- Modify: `Resources/Info.plist`

- [x] **Step 1: Bump the bundle build**

Set `CFBundleVersion` to `7`.

- [x] **Step 2: Build the app**

Run: `Scripts/build-app.sh`

Expected: `dist/OpenLoop ADHD.app` is produced and signed.

- [x] **Step 3: Install safely**

Confirm OpenLoop is not processing a job, quit it only if required, move the prior installed app to Trash, and copy build 7 to `/Applications/OpenLoop ADHD.app`. Do not launch it.

- [x] **Step 4: Commit the increment**

Commit the implementation, tests, plan, documentation, and build metadata with message `fix: make language detection automatic`.

## Self-review

- Spec coverage: automatic default, clean normal UI, Advanced-only override, Hindi auto-detection acceptance, installation, and no launch are all covered.
- Placeholder scan: no deferred implementation markers are present.
- Type consistency: all tasks use the existing `MeetingLanguagePreference`, `AppModel.setMeetingLanguagePreference`, and `MeetingTranscribing` language-code seam.
