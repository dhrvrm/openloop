# Advanced Mode Visual System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional native Advanced Mode that makes OpenLoop's complete local meeting pipeline observable, while upgrading the existing workspace into a calmer and more polished macOS interface.

**Architecture:** The meeting controller owns factual diagnostics and a bounded transition history; `AppModel` projects those values without adding pipeline policy. `MainView` keeps the existing four destinations and conditionally adds a right-side `AdvancedInspector` with a stage graph, live job metrics, model/cache/storage facts, and recent events. A small native visual system centralizes surfaces, spacing, typography, and status color so the default and advanced interfaces remain coherent.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Combine, UserDefaults, existing WhisperKit/SpeakerKit pipeline.

---

## Constraints

- Advanced Mode is off by default and persisted locally.
- It exposes real state only; no simulated logs, fake throughput, fabricated accuracy, or invented model status.
- Keep Now, Return, Later, and Recall as the only destinations.
- Use system typography, materials, SF Symbols, accessibility contrast, and reduced-motion-safe native transitions.
- Do not hide core controls behind Advanced Mode.
- Do not reveal the full home-directory path; show friendly app-relative storage locations.
- Event history is bounded to 40 entries and records stage transitions plus coarse progress milestones, not every token callback.
- Continue to avoid launching the app during automated work.
- Run focused tests and a release build, not the exhaustive verification gate.

## File map

- `Sources/OpenLoopApp/MeetingSystemDiagnostics.swift`: diagnostic values, pipeline nodes, and bounded event representation.
- `Sources/OpenLoopApp/LocalMeetingTranscriber.swift`: report factual model identifiers and cached/download-required state.
- `Sources/OpenLoopApp/MeetingTranscriptionController.swift`: publish diagnostics and transition/milestone history.
- `Sources/OpenLoopApp/AppModel.swift`: persist Advanced Mode and observe diagnostics/events.
- `Sources/OpenLoopApp/MainWindowController.swift`: native visual tokens, refined workspace chrome, sidebar toggle, pipeline inspector, and improved meeting surfaces.
- `Tests/OpenLoopAppTests/MeetingSystemDiagnosticsTests.swift`: node/status/event tests.
- `Tests/OpenLoopAppTests/MeetingTranscriptionControllerTests.swift`: transition history tests.
- `Tests/OpenLoopAppTests/MainWindowControllerTests.swift`: Advanced Mode persistence and layout-state tests.
- `README.md`: describe Advanced Mode and its factual visibility boundary.

### Task 1: Define factual diagnostics and event history

**Files:**
- Create: `Sources/OpenLoopApp/MeetingSystemDiagnostics.swift`
- Create: `Tests/OpenLoopAppTests/MeetingSystemDiagnosticsTests.swift`
- Modify: `Sources/OpenLoopApp/LocalMeetingTranscriber.swift`

- [x] Write tests proving the pipeline order is `Audio → Staging → Whisper → Speakers → Vault → Recall`, active/completed node projection follows `MeetingTranscriptionStage`, and friendly storage names contain no home path.
- [x] Implement `MeetingPipelineNode`, `MeetingPipelineEvent`, `MeetingEngineDiagnostics`, and deterministic node-state projection.
- [x] Extend `MeetingTranscribing` with `diagnostics() async`; provide a safe protocol default and a WhisperKit implementation that checks only the resolved-model marker and local folder existence.
- [x] Run `Scripts/test.sh --filter MeetingSystemDiagnosticsTests`.

### Task 2: Publish bounded controller telemetry

**Files:**
- Modify: `Sources/OpenLoopApp/MeetingTranscriptionController.swift`
- Modify: `Tests/OpenLoopAppTests/MeetingTranscriptionControllerTests.swift`

- [x] Write tests that import/recording creates ordered stage events, repeated progress inside one 10% bucket is deduplicated, and history never exceeds 40 entries.
- [x] Publish `engineDiagnostics` and `pipelineEvents`; refresh diagnostics before work and after model preparation.
- [x] Funnel every job mutation through one `apply(progress:)`/`recordEvent(...)` path and record terminal failures, cancellation, saving, and ready.
- [x] Run `Scripts/test.sh --filter MeetingTranscriptionControllerTests`.

### Task 3: Persist Advanced Mode in the app model

**Files:**
- Modify: `Sources/OpenLoopApp/AppModel.swift`
- Modify: `Tests/OpenLoopAppTests/MainWindowControllerTests.swift`

- [x] Write a test using an isolated `UserDefaults` suite that proves Advanced Mode defaults off, toggles on, and survives a new model instance.
- [x] Add injected `UserDefaults`, `advancedModeKey`, published `isAdvancedModeEnabled`, and `setAdvancedModeEnabled(_:)` without changing existing call sites.
- [x] Observe diagnostics and events from `MeetingTranscriptionController` into published model values.
- [x] Run the focused persistence test.

### Task 4: Add the native Advanced Inspector

**Files:**
- Modify: `Sources/OpenLoopApp/MainWindowController.swift`

- [x] Add an Advanced Mode switch at the bottom of the sidebar with explicit `slider.horizontal.3` iconography and active state.
- [x] Conditionally render a 300-point right inspector without adding a destination; increase the window's initial/minimum width only when needed by the responsive layout.
- [x] Render a vertical pipeline with directional relations, node state, live progress, local/cloud destination, model/cache facts, permission state, encrypted transcript count/bytes, friendly staging/cache locations, and recent timestamped events.
- [x] Add scroll behavior so the inspector remains usable at the minimum supported height.
- [x] Compile `OpenLoopApp`.

### Task 5: Apply the native visual-system pass

**Files:**
- Modify: `Sources/OpenLoopApp/MainWindowController.swift`

- [x] Centralize `OpenLoopVisualSystem` tokens for canvas, raised surfaces, corner radii, separators, status colors, and compact/display typography.
- [x] Refine the sidebar brand block, destination selection, screen headers, Quick Add, meeting job panel, transcript rows, and status banners using native surfaces and one teal accent.
- [x] Replace redundant labels and stacked generic cards in the primary capture path with sentence-case hierarchy, grouped regions, optical spacing, and quiet borders.
- [x] Add a short native opacity/offset transition and ensure animation respects `accessibilityReduceMotion`.
- [x] Compile and run focused UI/controller tests.

### Task 6: Package and install closed

**Files:**
- Modify: `Resources/Info.plist`
- Modify: `README.md`
- Modify: `.ai/plans/2026-08-18-advanced-mode-visual-system.md`

- [x] Increment the build number to 4 and document Advanced Mode.
- [x] Run focused diagnostics/controller/UI tests and `Scripts/build-app.sh`.
- [x] Replace `/Applications/OpenLoop ADHD.app` once, preserve build 3 in Trash, and leave build 4 closed.
- [x] Commit the increment with implementation evidence recorded here.

## Implementation evidence

- Focused verification: 6 tests passed covering node projection, friendly diagnostics, bounded/coarse event history, imported and recorded audio transitions, and persisted Advanced Mode.
- Release packaging: `Scripts/build-app.sh` completed for build 4.
- Installation: `/Applications/OpenLoop ADHD.app` reports build 4 and passes strict deep code-signature verification.
- Process state: no `OpenLoopADHD` process was running after installation.
