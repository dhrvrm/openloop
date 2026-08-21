# Calm Interface Increment 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the dashboard-like three-column shell with a calm, task-first two-pane interface while preserving every existing capture, voice, context, Ask, Act, and diagnostic capability.

**Architecture:** Keep the existing SwiftUI/AppKit application and `AppModel`. Introduce explicit navigation metadata, render grouped sidebar sections, make Advanced a native on-demand inspector, and change frequently used surfaces from nested panels to borderless list sections. No storage migration is required.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Swift Testing

---

### Task 1: Define task-first workspace navigation

**Files:**
- Create: `Sources/OpenLoopApp/WorkspaceNavigation.swift`
- Modify: `Sources/OpenLoopApp/MainWindowController.swift`
- Test: `Tests/OpenLoopAppTests/V1ReliabilityTests.swift`

- [ ] **Step 1: Write a failing navigation contract test**

Replace the old five-destination assertion with assertions for grouped Focus and Intelligence destinations, unique IDs/icons, and stable legacy tab mapping.

- [ ] **Step 2: Run the targeted test and record the known toolchain result**

Run: `swift test --filter V1ReliabilityTests`

Expected in a complete Swift 6.2 toolchain: the navigation assertion fails until the implementation exists. On the current machine, record the pre-existing `no such module 'Testing'` environment blocker and continue with executable-target compilation.

- [ ] **Step 3: Implement navigation types**

Create `WorkspaceDestination.ID`, `WorkspaceDestination.Group`, grouped destination arrays, flattening, index lookup, shortcut strings, and section metadata. Use stable raw integer IDs for window restoration.

- [ ] **Step 4: Switch `MainView` from integer indexing to destination IDs**

Keep `MainWindowController.show(tab:)` compatible by mapping legacy integers through `WorkspaceOrientation.destination(at:)`.

- [ ] **Step 5: Build the executable target**

Run: `swift build --target OpenLoopApp`

Expected: exit 0.

### Task 2: Expand the native visual system

**Files:**
- Modify: `Sources/OpenLoopApp/OpenLoopVisualSystem.swift`
- Modify: `Sources/OpenLoopApp/MainWindowController.swift`

- [ ] **Step 1: Add calm-shell metrics and semantic tokens**

Add sidebar width, content width, row heights, selection, hover, recording, separator, and inspector material tokens. Preserve system-aware light/dark behavior.

- [ ] **Step 2: Remove rounded-display typography and repeated panel borders from shell elements**

Use standard San Francisco typography, sentence-case labels, restrained accent, and whitespace-led hierarchy.

- [ ] **Step 3: Add reusable list-section and sidebar-section components**

Components must keep ordinary rows borderless and reserve raised surfaces for editing, floating capture, warnings, and the inspector.

- [ ] **Step 4: Build the executable target**

Run: `swift build --target OpenLoopApp`

Expected: exit 0.

### Task 3: Implement the two-pane shell and on-demand inspector

**Files:**
- Modify: `Sources/OpenLoopApp/MainWindowController.swift`
- Modify: `Sources/OpenLoopApp/AdvancedInspector.swift`
- Test: `Tests/OpenLoopAppTests/MainWindowControllerTests.swift`

- [ ] **Step 1: Add shell-state assertions**

Assert Advanced defaults off, remains persisted when explicitly enabled, and does not change the default window width.

- [ ] **Step 2: Replace the permanent inspector column**

Render sidebar and focused content as the base layout. Present `AdvancedInspector` through SwiftUI's native inspector, controlled by the existing persisted preference. Keep minimum window width independent of inspector visibility.

- [ ] **Step 3: Replace the Advanced switch with a compact button**

The control must show selected state, expose help text, and remain reachable by accessibility.

- [ ] **Step 4: Simplify Advanced internals**

Use disclosure groups for live signal, pipeline, engine, quality, and recent events; do not require Advanced for error recovery.

- [ ] **Step 5: Build the executable target**

Run: `swift build --target OpenLoopApp`

Expected: exit 0.

### Task 4: Make capture and task lists visually primary

**Files:**
- Modify: `Sources/OpenLoopApp/MainWindowController.swift`

- [ ] **Step 1: Add Inbox and Later focused surfaces**

Inbox shows captures needing a decision. Later shows held-safe captures. Both reuse existing review commands and encrypted evidence.

- [ ] **Step 2: Compact the capture composer**

Keep text, Record, Dictate, Import, live meter, stable/unstable partials, and privacy state. Reduce persistent container weight and make recording red.

- [ ] **Step 3: Convert ready work and semantic collections to borderless list sections**

Keep separators, direct row actions, and empty/error/loading states. Remove outer card borders from normal content.

- [ ] **Step 4: Build the executable target**

Run: `swift build --target OpenLoopApp`

Expected: exit 0.

### Task 5: Complete source checks

**Files:**
- Modify: `.ai/plans/2026-08-21-calm-interface-increment-1.md`

- [ ] **Step 1: Run formatting and placeholder checks**

Run: `git diff --check` and `rg -n '(TODO|FIXME|implement here|rest of code)' Sources/OpenLoopApp Tests/OpenLoopAppTests`.

Expected: no new matches and no whitespace errors.

- [ ] **Step 2: Compile the app once from fresh source state**

Run: `swift build --target OpenLoopApp`.

Expected: exit 0. Do not launch the GUI.

