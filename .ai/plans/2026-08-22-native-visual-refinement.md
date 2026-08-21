# Native Visual Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make OpenLoop's macOS workspace visually coherent at Things-like density, then polish interaction states and install the resulting release without launching it.

**Architecture:** Keep the current SwiftUI/AppKit shell and centralize visual decisions in `OpenLoopVisualSystem`. Component views consume semantic palette roles and a small spacing scale; ordinary content stays flat while editors and active processing states receive restrained elevation. The second increment adds consistent hover, pressed, focus, selection, recording, loading, and empty-state behavior without changing product logic.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Swift Package Manager, macOS 15+

---

### Task 1: Palette and density contracts

**Files:**
- Modify: `Sources/OpenLoopApp/OpenLoopVisualSystem.swift`
- Modify: `Tests/OpenLoopAppTests/V1ReliabilityTests.swift`

- [ ] **Step 1: Extend the visual contract test**

Add expectations for a compact four-point spacing scale, a narrower content measure, and adaptive neutral/color roles. Keep tests limited to deterministic scalar values because SwiftUI `Color` is not equatable.

- [ ] **Step 2: Run the focused test command**

Run: `swift test --filter V1ReliabilityTests.nativeWorkspaceGeometryKeepsOneCompactVisualRhythm`

Expected: the test fails if `Testing` is available because the new scalar tokens do not exist; on this machine, record the known `no such module 'Testing'` toolchain blocker once and continue with build verification.

- [ ] **Step 3: Implement semantic palette and spacing tokens**

Define compact spacing tokens (`4`, `8`, `12`, `20`, `32`), adaptive warm-neutral canvas/sidebar/raised surfaces, subdued semantic tints, a `680` point content measure, and explicit hover/pressed/focus colors. Keep recording red and task completion blue; use other hues only for navigation and semantic classification.

- [ ] **Step 4: Build the app target**

Run: `swift build --target OpenLoopApp`

Expected: `Build of target: 'OpenLoopApp' complete!`

- [ ] **Step 5: Commit the contract**

```bash
git add Sources/OpenLoopApp/OpenLoopVisualSystem.swift Tests/OpenLoopAppTests/V1ReliabilityTests.swift
git commit -m "refactor: calibrate native palette and spacing"
```

### Task 2: Workspace composition correction

**Files:**
- Modify: `Sources/OpenLoopApp/MainWindowController.swift`
- Modify: `Sources/OpenLoopApp/AdvancedInspector.swift`
- Modify: `Sources/OpenLoopApp/SemanticGraph3DView.swift`

- [ ] **Step 1: Tighten the sidebar and content frame**

Use the central spacing scale for sidebar groups, rows, bottom controls, screen headers, and the centered content column. Remove loose one-off padding and align all leading content to the same checkbox/text grid.

- [ ] **Step 2: Correct color distribution**

Use neutral text and surfaces for ordinary information. Reserve semantic colors for icons, section titles, status dots, recording, and selected graph nodes; remove broad tinted fills that make the interface look synthetic.

- [ ] **Step 3: Normalize row and section rhythm**

Make task, review, transcript, memory, recall, and semantic rows share the same title/metadata spacing, divider inset, hover fill, and accessory alignment. Keep active processing panels as the only raised content surfaces.

- [ ] **Step 4: Build the app target**

Run: `swift build --target OpenLoopApp`

Expected: `Build of target: 'OpenLoopApp' complete!`

- [ ] **Step 5: Commit the correction increment**

```bash
git add Sources/OpenLoopApp/MainWindowController.swift Sources/OpenLoopApp/AdvancedInspector.swift Sources/OpenLoopApp/SemanticGraph3DView.swift
git commit -m "feat: rebalance workspace color and density"
```

### Task 3: Interaction and state polish increment

**Files:**
- Modify: `Sources/OpenLoopApp/OpenLoopVisualSystem.swift`
- Modify: `Sources/OpenLoopApp/MainWindowController.swift`
- Modify: `Sources/OpenLoopApp/AdvancedInspector.swift`
- Modify: `Sources/OpenLoopApp/SemanticGraph3DView.swift`

- [ ] **Step 1: Add reusable interaction styles**

Add restrained hover, pressed, keyboard-focus, selected, destructive, and disabled treatments using existing SwiftUI primitives. Use spring or ease-out motion only; respect Reduce Motion.

- [ ] **Step 2: Apply states to primary interaction paths**

Apply the styles to sidebar navigation, quick capture, record/dictate/import actions, task rows, transcript controls, memory rows, graph controls, and advanced inspector disclosures.

- [ ] **Step 3: Polish loading, empty, error, and recording states**

Keep state messaging inline, align it to the content grid, and make microphone activity unmistakably red with stable decibel feedback. Avoid generic centered dashboard cards.

- [ ] **Step 4: Build and inspect source invariants**

Run: `swift build --target OpenLoopApp && git diff --check`

Expected: target build completes and `git diff --check` prints nothing.

- [ ] **Step 5: Commit the interaction increment**

```bash
git add Sources/OpenLoopApp/OpenLoopVisualSystem.swift Sources/OpenLoopApp/MainWindowController.swift Sources/OpenLoopApp/AdvancedInspector.swift Sources/OpenLoopApp/SemanticGraph3DView.swift
git commit -m "feat: polish native interaction states"
```

### Task 4: Package and install the latest app

**Files:**
- Generated: `.artifacts/app/OpenLoop ADHD.app`
- Install: `/Applications/OpenLoop ADHD.app`

- [ ] **Step 1: Verify build prerequisites**

Run: `xcrun --find metal` and verify an `mlx.metallib` is available or can be built. Do not package a transcription build without the matching MLX shader library.

- [ ] **Step 2: Build the application bundle**

Run: `OPENLOOP_SIGN_IDENTITY=- Scripts/build-app.sh`

Expected: code signing verification succeeds and the script prints the generated app path.

- [ ] **Step 3: Install recoverably without launching**

Move the existing `/Applications/OpenLoop ADHD.app` into a timestamped backup location, copy the newly built bundle into `/Applications`, and verify its code signature and bundle version. Do not call `open`.

- [ ] **Step 4: Verify installed artifact**

Run `codesign --verify --deep --strict`, inspect `Info.plist`, and compare the installed executable hash with the generated executable.

Expected: signature verification exits zero and hashes match.

- [ ] **Step 5: Report the exact packaging blocker if prerequisites remain unavailable**

If the host still has only Command Line Tools and no Metal compiler, report that production source and binary compilation succeeded but installation was deliberately withheld to avoid shipping a bundle that can crash when local MLX transcription initializes.
