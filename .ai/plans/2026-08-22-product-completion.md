# OpenLoop Product Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert OpenLoop's existing voice, task, memory, UI, website, and release foundations into complete end-to-end product behavior with truthful acceptance gates.

**Architecture:** Preserve the ports-and-adapters domain core. Fix system boundaries in dependency order: stable encrypted data access, immediate shared audio capture, bounded recognition, visible session state, evidence-backed semantic enrichment, then external actions and distribution. Raw evidence remains immutable; interpretations and actions remain separate and permission-aware.

**Tech Stack:** Swift 6.2, AppKit/SwiftUI, AVFoundation, MLX Qwen3-ASR, WhisperKit, Silero VAD, CryptoKit, Swift Testing, React/Vite, GSAP, GitHub Actions

---

### Task 1: Stabilize release data access and retention

**Files:**
- Modify: `Sources/OpenLoopApp/App/OpenLoopApp.swift`
- Modify: `Sources/OpenLoopApp/Context/LocalPrivacyManager.swift`
- Modify: `Resources/Info.plist`
- Test: `Tests/VaultStoreTests/EncryptedThoughtRepositoryTests.swift`
- Test: `Tests/OpenLoopAppTests/V1ReliabilityTests.swift`

- [ ] **Step 1: Add a failing development-to-release key migration test**

Create a local file key, encrypt a record, reopen through `MigratingLocalVaultKeyProvider(fileURL:fallback:)`, and assert the same record decrypts while the fallback is not called when `root-key.local` exists.

- [ ] **Step 2: Compose the migration-safe provider**

Use `LocalFileVaultKeyProvider` for explicit development builds and
`MigratingLocalVaultKeyProvider(fileURL: root-key.local, fallback: KeychainVaultKeyProvider(...))`
for release builds. Existing local-key vaults open without Keychain; existing
Keychain vaults migrate once to a protected 0600 local key.

- [ ] **Step 3: Make retention copy truthful**

Change the microphone usage description to state that retry audio is retained
locally until the user deletes it or retention removes it. Add staged-audio
totals and removal to the privacy manager's reset contract.

- [ ] **Step 4: Run focused verification**

Run `swift build --target OpenLoopApp`, `git diff --check`, and the GitHub native
test job. Expected: build exit 0 and migration/reset tests pass.

- [ ] **Step 5: Commit**

Run `git add Sources/OpenLoopApp/App/OpenLoopApp.swift Sources/OpenLoopApp/Context/LocalPrivacyManager.swift Resources/Info.plist Tests && git commit -m "fix: stabilize release vault migration"`.

### Task 2: Start recording before model preparation

**Files:**
- Modify: `Sources/OpenLoopApp/Meetings/MeetingAudioRecorder.swift`
- Modify: `Sources/OpenLoopApp/Meetings/MeetingTranscriptionController.swift`
- Modify: `Sources/OpenLoopApp/Voice/StreamingVoiceSession.swift`
- Test: `Tests/OpenLoopAppTests/MeetingTranscriptionControllerTests.swift`
- Test: `Tests/OpenLoopAppTests/StreamingVoiceSessionTests.swift`

- [ ] **Step 1: Add a gated model-preparation test**

Use an async latch in the fake streaming builder. Call `toggleRecording()`, keep
model preparation blocked, and assert the recorder has already started and job
state is `.recording`.

- [ ] **Step 2: Reverse the startup dependency**

Create the staging URL and start durable recording first. Prepare streaming in
a child task. When streaming becomes ready, connect future frames; batch
transcription remains the lossless final path for audio captured before readiness.

- [ ] **Step 3: Coalesce partial inference**

Change `StreamingVoiceFramePump` to allow one ingest/decode operation in flight,
retain only the newest pending frame batch, and make `finish()` flush the latest
pending audio without replaying an unbounded queue.

- [ ] **Step 4: Verify timing behavior**

Run the two focused test files and `swift build --target OpenLoopApp`. Expected:
recording state is observable before the latch opens and stop completes without
draining one task per historical frame.

- [ ] **Step 5: Commit**

Commit with `git commit -m "fix: start voice capture before model loading"`.

### Task 3: Wire one global dictation HUD and transcript destination

**Files:**
- Modify: `Sources/OpenLoopApp/UI/VoiceCaptureWindowController.swift`
- Modify: `Sources/OpenLoopApp/App/OpenLoopApp.swift`
- Modify: `Sources/OpenLoopApp/App/AppModel.swift`
- Modify: `Sources/OpenLoopApp/App/WorkspaceNavigation.swift`
- Modify: `Sources/OpenLoopApp/App/MainWindowController.swift`
- Test: `Tests/OpenLoopAppTests/MainWindowControllerTests.swift`

- [ ] **Step 1: Replace the legacy controller dependency**

Make the floating `NSPanel` observe `AppModel` and render the shared
`meetingJob`, `recordingDecibels`, `streamingVoiceSession`, processing, and
delivery state. The panel must be non-activating and must not steal focus from
the destination application.

- [ ] **Step 2: Add deterministic HUD visibility rules**

Show during system dictation recording and processing; show success briefly;
persist failures until dismissed. Stop and cancel controls call the same model
commands as the main window.

- [ ] **Step 3: Add a Transcripts destination**

Add `WorkspaceDestination.transcripts`, select the newest completed transcript,
and keep raw transcript, evidence, summary, decisions, questions, and action
candidates together.

- [ ] **Step 4: Remove duplicate voice presentation code**

Use one recording meter/transcript component family in the Now surface, global
HUD, and transcript destination. Remove dormant `VoiceInlineStatus` and the old
Apple-Speech-only HUD path.

- [ ] **Step 5: Verify without launching the GUI**

Add model/window-controller tests for visibility rules and navigation, then run
`swift build --target OpenLoopApp` and GitHub CI.

### Task 4: Decode bounded multilingual spans and resolve disagreements

**Files:**
- Modify: `Sources/OpenLoopApp/Meetings/QwenMeetingTranscriber.swift`
- Modify: `Sources/OpenLoopApp/Meetings/LocalMeetingTranscriber.swift`
- Modify: `Sources/OpenLoopApp/Voice/AccuracyFirstTranscriber.swift`
- Modify: `Sources/OpenLoopApp/Voice/CodeSwitchChunkPlanner.swift`
- Modify: `Sources/ADHDCore/TranscriptFusion.swift`
- Test: `Tests/OpenLoopAppTests/QwenMeetingTranscriberTests.swift`
- Test: `Tests/OpenLoopAppTests/AccuracyFirstTranscriberTests.swift`
- Test: `Tests/OpenLoopAppTests/CodeSwitchChunkPlannerTests.swift`

- [ ] **Step 1: Add long-form and short-switch failures**

Cover a 25-minute sample plan, a two-second Hindi tail after English, romanized
Hinglish, repeated/empty spans, and a witness candidate that is better than the
primary.

- [ ] **Step 2: Segment all durations**

Decode 10–20 second VAD speech spans with overlap and absolute timestamps.
Never send a complete meeting through one token-limited Qwen request.

- [ ] **Step 3: Expand ensemble risk detection**

Pass learned vocabulary into `AccuracyFirstTranscriber`. Escalate on missing
terms, improbable script/language sequences, short switches, repetition, empty
spans, and disagreement—not only already-correct mixed-script output.

- [ ] **Step 4: Make disagreement user-visible or fused**

Fuse exact agreements and confidence-supported spans. Where evidence remains
ambiguous, retain both candidates and require review; never silently retain a
known-disputed primary.

- [ ] **Step 5: Add representative release fixtures**

Store consented or generated non-private audio for English, Hindi, romanized
Hinglish, mixed language, technical terms, noise, and long-form boundaries.
Release gates must fail when required fixtures are absent rather than returning
success without running.

### Task 5: Persist structured meeting and semantic intelligence

**Files:**
- Modify: `Sources/ADHDCore/MeetingIntelligence.swift`
- Create: `Sources/OpenLoopApp/Meetings/LocalMeetingIntelligenceProvider.swift`
- Modify: `Sources/ADHDCore/SemanticGraph.swift`
- Modify: `Sources/ADHDCore/SemanticGraphLoop.swift`
- Modify: `Sources/OpenLoopApp/App/AppModel.swift`
- Test: `Tests/ADHDCoreTests/MeetingIntelligenceTests.swift`
- Test: `Tests/ADHDCoreTests/SemanticGraphLoopTests.swift`

- [ ] **Step 1: Define versioned interpretation records**

Persist provider/model/schema version, summary, decisions, questions, action
candidates, confidence, and exact transcript evidence spans separately from raw
transcript records.

- [ ] **Step 2: Add local structured extraction with validation**

Use the local Qwen chat model to emit a bounded schema. Reject missing evidence,
invalid confidence, unsupported node kinds, and text not anchored to transcript
spans; fall back to the deterministic compiler.

- [ ] **Step 3: Extract multiple semantic objects per utterance**

Create provisional problems, observations, ideas, possibilities, decisions,
intentions, people, projects, and concepts. Preserve uncertainty; “maybe” cannot
become a decision or task.

- [ ] **Step 4: Link and consolidate**

Combine multilingual vector similarity, named entities, explicit references,
and recurrence. Add append-only consolidation/supersession events without
deleting episode evidence.

- [ ] **Step 5: Upgrade Ask and Emerging**

Rank lexical, vector, graph, recency, confidence, and evidence signals. Return
cited nodes and belief history; show “not enough evidence” instead of invention.

### Task 6: Complete the native task interaction model

**Files:**
- Modify: `Sources/ADHDCore/Intention.swift`
- Modify: `Sources/ADHDCore/ReadModels.swift`
- Modify: `Sources/OpenLoopApp/App/WorkspaceNavigation.swift`
- Modify: `Sources/OpenLoopApp/App/MainWindowController.swift`
- Modify: `Sources/OpenLoopApp/UI/OpenLoopVisualSystem.swift`
- Test: `Tests/ADHDCoreTests/IntentionTests.swift`
- Test: `Tests/OpenLoopAppTests/MainWindowControllerTests.swift`

- [ ] **Step 1: Add domain move transactions**

Represent source, destination, relative position, selected IDs, and inverse
operation. Persist atomically and expose Undo.

- [ ] **Step 2: Add destinations and structures**

Implement Upcoming, Someday, Spaces/Threads, headings, checklists, dates, and
tags as domain data—not transient view state.

- [ ] **Step 3: Add interaction parity**

Wire sidebar drops, row-before/after drops, multi-selection, Move sheet,
Command-Up/Down movement, top/bottom movement, and accessible equivalents.

- [ ] **Step 4: Add Quick Find and window modes**

Implement type-to-travel, resizable/collapsible split view, Slim mode, and
independent navigation per window.

- [ ] **Step 5: Reconcile the visual source of truth**

Align native measurements with `DESIGN.md`: 252-point default sidebar, 760-point
reading measure, 34-point rows, 18/28 checkbox, 28–40-point major section gaps,
warm neutral/graphite/jade palette, and red only for recording/error.

### Task 7: Add permission-aware external capabilities

**Files:**
- Create: `Sources/OpenLoopApp/Actions/CapabilityRegistry.swift`
- Create: `Sources/OpenLoopApp/Actions/MCPRouter.swift`
- Create: `Sources/OpenLoopApp/Actions/ActionExecutor.swift`
- Modify: `Sources/ADHDCore/CapabilityGraph.swift`
- Modify: `Sources/OpenLoopApp/App/MainWindowController.swift`
- Test: `Tests/ADHDCoreTests/CapabilityGraphTests.swift`

- [ ] **Step 1: Persist Observe/Suggest/Act grants**

Default every discovered capability to Observe only. Act requires an explicit
tool/action grant; destructive actions always require per-action confirmation.

- [ ] **Step 2: Discover and normalize MCP tools**

Map server tools into stable capabilities with input schemas, risk class,
availability, and audit metadata. Never require users to name an MCP server.

- [ ] **Step 3: Prepare before acting**

Render intent, chosen capability, exact parameters, evidence, and expected side
effects. Persist the proposal and confirmation before execution.

- [ ] **Step 4: Add audit and recovery**

Persist result, failure, cancellation, and any available inverse action. Tool
failure cannot mutate semantic evidence into a false success state.

### Task 8: Finish website and public distribution

**Files:**
- Modify: `website/src/App.tsx`
- Modify: `website/src/styles.css`
- Modify: `website/index.html`
- Create: `website/public/404.html`
- Create: `website/public/privacy.html`
- Modify: `.github/workflows/release.yml`
- Modify: `Scripts/configure-github.sh`

- [ ] **Step 1: Replace stale failure imagery**

Use current successful-state captures for idle work, red recording with dB,
mixed Hindi/English transcript, and semantic evidence. Do not double-frame an
already framed screenshot.

- [ ] **Step 2: Make marketing controls truthful**

Remove dead buttons or make demos functional. Link the primary CTA directly to
the versioned DMG; show version, size, checksum, requirements, install steps,
and ad-hoc signing disclosure.

- [ ] **Step 3: Finish accessibility and metadata**

Add skip navigation, mobile navigation, favicon/app icon, canonical URL,
Open Graph/Twitter metadata, structured data, privacy, license, accessibility,
and a branded 404.

- [ ] **Step 4: Add stable signed release inputs**

Keep community builds explicit. When Developer ID and notary secrets exist,
sign, notarize, staple, verify Gatekeeper assessment, then publish the DMG and
checksum. Never label ad-hoc output as notarized.

- [ ] **Step 5: Apply repository settings with authority**

From an admin-authenticated GitHub CLI session, run
`Scripts/configure-github.sh`, enable Pages, and verify the homepage, topics,
description, release link, and direct DMG HTTP response.

### Completion gate

- [ ] Every row in `docs/COMPLETION_LEDGER.md` is either **Shipped** with fresh
  evidence or **Blocked** with one explicit external credential/authority.
- [ ] Representative English, Hindi, romanized-Hinglish, mixed-language, noisy,
  technical, and 25-minute fixtures run in release CI.
- [ ] The installed DMG matches its published checksum, opens the existing vault,
  records immediately, shows a global HUD, and leaves the app closed after
  installation verification.
- [ ] Public claims do not exceed measured evidence.
