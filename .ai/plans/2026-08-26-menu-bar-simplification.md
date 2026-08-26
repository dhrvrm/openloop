# Menu-bar simplification implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace OpenLoop's overloaded status menu with five plain controls and show live voice state directly in the macOS menu bar.

**Architecture:** Add a pure presentation projection that converts current recording, dictation, delivery, and continuous-listening state into menu titles, enabled states, checkmarks, icon names, and a short menu-bar label. Keep AppKit wiring in `AppDelegate`, subscribe it to the existing `AppModel` publishers, and leave workspace navigation inside the main window.

**Tech Stack:** Swift 6.2, AppKit, Combine, Swift Testing, Swift Package Manager.

---

### Task 1: Specify the minimal menu presentation

**Files:**
- Create: `Sources/OpenLoopApp/App/StatusMenuPresentation.swift`
- Create: `Tests/OpenLoopAppTests/StatusMenuPresentationTests.swift`

- [x] **Step 1: Write failing projection tests**

Cover idle, voice-note recording, voice typing, transcription, delivery, and continuous-listening states. Assert that the only commands are `openOpenLoop`, `voiceNote`, `voiceTyping`, `keepListening`, and `quit`, and that legacy workspace terms do not appear.

- [x] **Step 2: Run the focused tests and confirm failure**

Run: `Scripts/test.sh --filter StatusMenuPresentationTests`

Expected: compilation fails because `StatusMenuPresentation` does not exist.

- [x] **Step 3: Implement the pure projection**

Create an internal `StatusMenuCommand` enum and `StatusMenuPresentation` value with a `make(...)` factory. Use these exact user-facing outcomes:

- idle menu-bar label: empty;
- recording label: `Listening`;
- dictation label: `Typing`;
- processing label: `Transcribing`;
- delivery label: `Writing`;
- voice action: `Start Voice Note` or `Stop Voice Note`;
- dictation action: `Type by Voice` or `Stop Voice Typing`;
- continuous action: `Keep Listening` with a checkmark when enabled.

Mutually active voice modes disable the other start action. Keep-listening remains controllable and reflects persisted state.

- [x] **Step 4: Run the focused tests and confirm pass**

Run: `Scripts/test.sh --filter StatusMenuPresentationTests`

Expected: all status-menu presentation tests pass.

### Task 2: Replace the AppKit status menu

**Files:**
- Modify: `Sources/OpenLoopApp/App/OpenLoopApp.swift`

- [x] **Step 1: Wire five menu commands**

Replace the flat navigation/focus/privacy menu with this exact order:

1. `Open OpenLoop`
2. `Start Voice Note` / `Stop Voice Note`
3. `Type by Voice` / `Stop Voice Typing`
4. `Keep Listening`
5. separator
6. `Quit OpenLoop`

Keep the existing global shortcut equivalents on the two voice actions. Remove the menu-only selectors and item references for text capture, workspace tabs, pause/continue, and context collection.

- [x] **Step 2: Subscribe the status item to model state**

Use Combine to project `meetingJob`, `isSystemDictationActive`, `isDeliveringDictation`, and `keepListeningEnabled`. Update the status icon, optional short title, menu item titles, enabled states, and checkmark on the main actor whenever state changes.

- [x] **Step 3: Run focused tests**

Run: `Scripts/test.sh --filter StatusMenuPresentationTests`

Expected: all status-menu presentation tests pass.

### Task 3: Version, verify, package, and install

**Files:**
- Modify: `Resources/Info.plist`
- Modify: `CHANGELOG.md`

- [x] **Step 1: Record release 1.0.10 build 23**

Add a 1.0.10 changelog entry describing the five-control status menu and live menu-bar state. Update comparison links.

- [x] **Step 2: Run deterministic verification**

Run: `Scripts/test.sh`

Expected: the complete test suite passes with zero failures.

- [x] **Step 3: Build and verify the release bundle**

Run the existing release scripts with ad-hoc community signing and the explicitly supplied prebuilt MLX Metal library from the currently installed app. Do not launch the app.

- [x] **Step 4: Install without disturbing the running process**

Replace `/Applications/OpenLoop ADHD.app` using `ditto`, verify its version and signature on disk, and do not terminate or relaunch the old process.

- [ ] **Step 5: Commit, tag, push, and publish the DMG**

Commit the focused change, fast-forward `main`, push both branches and tag `v1.0.10`, then confirm the GitHub release exposes the DMG and checksum.
