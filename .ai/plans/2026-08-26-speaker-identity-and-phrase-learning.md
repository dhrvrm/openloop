# Speaker Identity and Phrase Learning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Separate speakers as A/B/C, let the user assign aliases, recognize enrolled voices across later recordings, expose diarization failure, and learn exact corrected phrases after one explicit edit.

**Architecture:** Preserve SpeakerKit centroid observations inside the encrypted meeting transcript and resolve them against prior observations with conservative cosine-distance and ambiguity gates. Speaker identity remains grounded in stored audio-derived evidence: segments carry a profile ID and visible alias, while renaming updates every transcript connected to that profile. A transcription wrapper applies minimal phrase corrections to both meeting and dictation output before persistence.

**Tech Stack:** Swift 6.2, SpeakerKit/Pyannote centroids, existing encrypted vault, Swift Testing.

---

### Task 1: Add backward-compatible speaker evidence

**Files:**
- Modify: `Sources/ADHDCore/MeetingTranscription.swift`
- Test: `Tests/ADHDCoreTests/MeetingTranscriptionTests.swift`

- [x] **Step 1: Test legacy transcript decoding, segment profile IDs, separation state, and encrypted fingerprint observations.**
- [x] **Step 2: Add `SpeakerSeparationState`, `SpeakerFingerprintObservation`, optional `speakerProfileID` on `TranscriptSegment`, and default-empty observations on `MeetingTranscript`.**
- [x] **Step 3: Preserve legacy Codable defaults so existing vaults decode as `.notRequested` with no fingerprints.**

### Task 2: Preserve diarization and resolve identities

**Files:**
- Create: `Sources/OpenLoopApp/Meetings/SpeakerIdentityResolver.swift`
- Modify: `Sources/OpenLoopApp/Meetings/LocalMeetingTranscriber.swift`
- Modify: `Sources/OpenLoopApp/Voice/AccuracyFirstTranscriber.swift`
- Modify: `Sources/OpenLoopApp/Meetings/MeetingTranscriptionController.swift`
- Test: `Tests/OpenLoopAppTests/SpeakerIdentityResolverTests.swift`
- Test: `Tests/OpenLoopAppTests/LocalMeetingTranscriberTests.swift`

- [x] **Step 1: Test A/B/C label generation, conservative same-voice matching, ambiguity rejection, one-profile-per-local-speaker matching, and alias reuse.**
- [x] **Step 2: Export SpeakerKit centroids beside aligned segments and mark separation `.complete(count:)`; mark caught diarization failures `.unavailable` instead of hiding them.**
- [x] **Step 3: Preserve primary speaker evidence through accuracy-first text fusion.**
- [x] **Step 4: Resolve current centroids against encrypted history before saving, assigning new profile IDs and A/B/C aliases only when no safe match exists.**

### Task 3: Make speaker aliases editable and durable

**Files:**
- Modify: `Sources/OpenLoopApp/Meetings/MeetingTranscriptionController.swift`
- Modify: `Sources/OpenLoopApp/App/AppModel.swift`
- Modify: `Sources/OpenLoopApp/App/MainWindowController.swift`
- Test: `Tests/OpenLoopAppTests/MeetingTranscriptionControllerTests.swift`

- [x] **Step 1: Test that renaming one profile updates every connected transcript while leaving unrelated speakers unchanged.**
- [x] **Step 2: Add the controller/model rename operation using the existing encrypted transcript saves.**
- [x] **Step 3: Add an inline speaker-name editor and visible `N speakers` / `Speaker separation unavailable` status to each transcript card.**

### Task 4: Learn “tip for tap” after an explicit correction

**Files:**
- Modify: `Sources/ADHDCore/VoiceLearning.swift`
- Create: `Sources/OpenLoopApp/Voice/TranscriptNormalizingTranscriber.swift`
- Modify: `Sources/OpenLoopApp/App/OpenLoopApp.swift`
- Test: `Tests/ADHDCoreTests/VoiceLearningTests.swift`
- Test: `Tests/OpenLoopAppTests/TranscriptNormalizingTranscriberTests.swift`

- [x] **Step 1: Test minimal replacement extraction: `tit-for-tat` → `tip for tap`, without turning an entire paragraph into a vocabulary entry.**
- [x] **Step 2: Let one explicit personal correction create a token-anchored normalization rule.**
- [x] **Step 3: Apply current encrypted correction rules to every final meeting and dictation segment while preserving timing, speaker, profile, and fusion evidence.**

### Task 5: Verify and ship the increment

**Files:**
- Modify: `docs/VOICE_PLATFORM.md`

- [x] **Step 1: Document fingerprint locality, conservative matching, aliases, failure visibility, and correction behavior.**
- [ ] **Step 2: Run focused builds/tests without launching the app, then run the full Xcode CI suite.**
- [ ] **Step 3: Push the verified commits to the feature branch and `main`; do not open OpenLoop automatically.**
