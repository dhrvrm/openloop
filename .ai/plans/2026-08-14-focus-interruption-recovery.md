# Focus and Interruption Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let one intention enter a durable focus session, show a calm elapsed-time cue, capture an exact interruption packet, survive application termination, and resume with the same next action and references.

**Architecture:** `ADHDCore` owns a focus-session state machine, interruption composer, orchestration service, and Now/Return projections. `ThoughtRepository` gains defaulted focus queries plus one atomic intention/session write; both local adapters persist focus sessions in backward-compatible snapshots. `OpenLoopApp` supplies an optional frontmost-application reference, exposes focused controls through Now and the menu bar, and renders Return packets without backlog pressure. A packaged diagnostic interrupts a real encrypted session, reopens the vault, compares the packet exactly, resumes it, and exits nonzero on any mismatch.

**Tech Stack:** Swift 6.2, Swift Package Manager, Swift Testing, SwiftUI, AppKit/NSWorkspace, CryptoKit AES-GCM, Security Keychain Services, zsh packaging diagnostics.

---

## Constraints

- Preserve all Increment 0 and Increment 1 behavior, including instant Quick Capture and legacy vault readability.
- Permit at most one current focus session (`active` or `paused`); interrupted sessions live in Return and do not block a new current intention.
- Keep focus timing monotonic within the supplied wall-clock dates: negative clock movement contributes zero elapsed time.
- Keep `Intention` and `FocusSession` changes in one repository write at lifecycle boundaries so a crash cannot persist half a transition.
- Interruption requires an exact nonempty next action. Optional text is trimmed to `nil`; references are trimmed, empty values removed, and duplicates removed in first-seen order.
- Context collection is optional and failure-tolerant. Manual references always survive even when the local adapter returns nothing.
- Return displays desired outcome, just-completed work, exact next action, blocker, references, and captured time. It uses neutral language and no overdue, streak, score, urgency, or notification debt.
- The elapsed-time cue is descriptive, not a target or countdown.
- Do not add accounts, network access, telemetry, notifications, voice, search, ambient capture, or a formal `SUBSYSTEM.md` graph.

## File map

- `Sources/ADHDCore/FocusSession.swift`: focus state machine and elapsed-time calculation.
- `Sources/ADHDCore/InterruptionSnapshot.swift`: draft, optional context-provider port, and packet composer.
- `Sources/ADHDCore/FocusLoop.swift`: one-session orchestration and atomic lifecycle transitions.
- `Sources/ADHDCore/Ports.swift`: focus persistence/query contract with compatibility defaults.
- `Sources/ADHDCore/ReadModels.swift`: focus-aware Now and Return projections.
- `Sources/LocalStore/JSONFileThoughtRepository.swift`: backward-compatible development snapshot persistence.
- `Sources/VaultStore/EncryptedThoughtRepository.swift`: backward-compatible encrypted focus persistence.
- `Sources/OpenLoopApp/FrontmostApplicationReferenceProvider.swift`: optional local application reference.
- `Sources/OpenLoopApp/AppModel.swift`: focus commands and published Return state.
- `Sources/OpenLoopApp/MainWindowController.swift`: interactive Now, interruption sheet, Return, and calm clock.
- `Sources/OpenLoopApp/OpenLoopApp.swift`: production wiring, menu actions, and packaged restart diagnostic.
- `Scripts/verify-increment-2.sh`: complete Increment 2 exit gate.

### Task 1: Define and prove the focus-session state machine

**Files:**
- Create: `Sources/ADHDCore/FocusSession.swift`
- Create: `Tests/ADHDCoreTests/FocusSessionTests.swift`

- [x] **Step 1: Write failing state and timing tests**

Cover creation in `active`, pausing with accrued elapsed time, continuing a paused session, interrupting from active or paused, resuming an interrupted session, finishing, invalid transitions, and a backward clock that never subtracts elapsed time.

- [x] **Step 2: Verify focused failure**

Run `Scripts/test.sh --filter FocusSessionTests`.

Expected: compilation fails because `FocusSession` and `FocusSessionState` do not exist.

- [x] **Step 3: Implement the value state machine**

`FocusSession` contains `id`, `intentionID`, `startedAt`, `state`, `accumulatedSeconds`, and optional `activeSince`. Its mutating commands are `pause(at:)`, `continue(at:)`, `interrupt(at:)`, `resume(at:)`, and `finish(at:)`; `elapsed(at:)` returns accumulated seconds plus the current active interval only while active.

- [x] **Step 4: Run tests and commit**

Run `Scripts/test.sh --filter FocusSessionTests && Scripts/test.sh --filter ADHDCoreTests`.

Commit: `feat: add durable focus session state machine`.

### Task 2: Compose exact interruption snapshots and orchestrate focus

**Files:**
- Create: `Sources/ADHDCore/InterruptionSnapshot.swift`
- Create: `Sources/ADHDCore/FocusLoop.swift`
- Modify: `Sources/ADHDCore/Ports.swift`
- Create: `Tests/ADHDCoreTests/InterruptionSnapshotTests.swift`
- Create: `Tests/ADHDCoreTests/FocusLoopTests.swift`

- [x] **Step 1: Write failing composer tests**

Verify whitespace normalization, stable reference de-duplication, manual-plus-provider ordering, empty next-action rejection, and provider failure falling back to manual references.

- [x] **Step 2: Write failing orchestration tests**

Verify start creates one focus session with the intention active; a second current session is rejected; pause/continue persist timing; interrupt atomically stores the exact packet and interrupted session; resume restores the packet next action; finish closes both values; and missing IDs produce typed errors.

- [x] **Step 3: Extend the repository contract compatibly**

Add `save(intention:focusSession:)`, `save(focusSession:)`, `focusSession(id:)`, and `focusSessions()` requirements. Supply safe default implementations so existing test doubles and third-party adapters still compile; production adapters override the combined save atomically.

- [x] **Step 4: Implement the composer and `FocusLoop`**

`InterruptionSnapshotComposer` accepts an optional `ContextReferenceProvider` and builds the existing `ReturnPacket`. `FocusLoop` owns start, pause, continue, interrupt, resume, and finish. It enforces one current session and writes intention/session pairs through the combined repository method at every coupled transition.

- [x] **Step 5: Run tests and commit**

Run `Scripts/test.sh --filter 'InterruptionSnapshotTests|FocusLoopTests' && Scripts/test.sh --filter ADHDCoreTests`.

Commit: `feat: preserve interruption context through focus orchestration`.

### Task 3: Persist focus state in both repositories without breaking old data

**Files:**
- Modify: `Sources/LocalStore/JSONFileThoughtRepository.swift`
- Modify: `Sources/VaultStore/EncryptedThoughtRepository.swift`
- Modify: `Tests/LocalStoreTests/JSONFileThoughtRepositoryTests.swift`
- Modify: `Tests/VaultStoreTests/EncryptedThoughtRepositoryTests.swift`

- [x] **Step 1: Write failing persistence and compatibility tests**

For both adapters, persist an intention/session pair, reopen, and compare both values. For the vault, also create a schema-1 encrypted snapshot without `focusSessions` and prove it still opens. Verify a packet's next action and references do not appear as plaintext in any vault file.

- [x] **Step 2: Add optional snapshot fields**

Add `[UUID: FocusSession]` to both snapshot values and custom decoders that default a missing field to an empty dictionary. Keep the existing authenticated-data string so schema-1 vaults remain decryptable.

- [x] **Step 3: Implement atomic production writes and stable reads**

Both repositories override `save(intention:focusSession:)` with one snapshot persistence operation. Focus-session reads use stable start-date/UUID ordering. Vault `empty`, counts, import, and legacy export retain their existing semantics; focus sessions are independent of Increment 0 migration.

- [x] **Step 4: Run tests and commit**

Run `Scripts/test.sh --filter 'LocalStoreTests|VaultStoreTests' && Scripts/test.sh`.

Commit: `feat: persist focus recovery state in the encrypted vault`.

### Task 4: Project focused Now and durable Return views

**Files:**
- Modify: `Sources/ADHDCore/ReadModels.swift`
- Modify: `Tests/ADHDCoreTests/ReadModelsTests.swift`

- [ ] **Step 1: Write failing read-model tests**

Verify Now exposes an open intention as startable, exposes current focus timing/state, omits interrupted intentions, and never chooses an unrelated open item over a current session. Verify Return contains only interrupted intentions with exact packet fields in newest-packet-first order.

- [ ] **Step 2: Implement projections**

Extend `NowItem` with an optional focus-session projection and a deterministic `elapsed(at:)`. Add `ReturnItem` with all restart context. `now()` joins intentions to focus sessions and `returns()` emits only valid interrupted packets.

- [ ] **Step 3: Run tests and commit**

Run `Scripts/test.sh --filter ReadModelsTests && Scripts/test.sh --filter ADHDCoreTests`.

Commit: `feat: project focused Now and exact Return packets`.

### Task 5: Add native focus, interrupt, and Return interactions

**Files:**
- Create: `Sources/OpenLoopApp/FrontmostApplicationReferenceProvider.swift`
- Modify: `Sources/OpenLoopApp/AppModel.swift`
- Modify: `Sources/OpenLoopApp/MainWindowController.swift`
- Modify: `Sources/OpenLoopApp/OpenLoopApp.swift`
- Create: `Tests/OpenLoopAppTests/FrontmostApplicationReferenceProviderTests.swift`

- [ ] **Step 1: Test the local reference adapter seam**

Inject a frontmost-application lookup closure and verify a named application becomes one readable reference while missing data yields none. Production uses `NSWorkspace.shared.frontmostApplication`; no Accessibility or Automation permission is requested.

- [ ] **Step 2: Extend `AppModel` commands**

Publish Return items and command errors. Add start, pause, continue, interrupt, resume, and finish methods that call `FocusLoop` then refresh. Keep capture acceptance and clarification behavior unchanged.

- [ ] **Step 3: Build interactive Now and interruption capture**

Now shows only outcome, exact next action, a neutral elapsed cue, and controls appropriate to the current focus state. Interrupt opens a compact sheet for just completed, exact next action, blocker, and newline-separated references; its next action defaults to the current one.

- [ ] **Step 4: Build Return and menu controls**

Add Return between Now and Later. Each packet displays all available recovery fields and Resume/Finish actions. The status menu exposes Capture, Now, Pause/Continue when applicable, Return, Later, a visible Private Mode item explaining that no sensing is active, and Quit.

- [ ] **Step 5: Wire production services and run tests**

Create `FocusLoop` with the encrypted repository and frontmost-app provider. Run `Scripts/test.sh --filter OpenLoopAppTests && Scripts/test.sh && swift build -c release`.

Commit: `feat: add calm focus and Return surfaces`.

### Task 6: Prove relaunch recovery and package Increment 2

**Files:**
- Modify: `Sources/OpenLoopApp/OpenLoopApp.swift`
- Create: `Scripts/verify-increment-2.sh`
- Modify: `README.md`
- Modify: `docs/DECISIONS.md`
- Modify: `.ai/plans/2026-08-14-focus-interruption-recovery.md`

- [ ] **Step 1: Add a packaged focus recovery diagnostic**

`--focus-recovery-test` creates a unique action, starts it, interrupts it with distinctive just-completed text, next action, blocker, and references, then opens a new encrypted repository instance. It asserts the stored intention and session are interrupted, compares every packet field, resumes through a new `FocusLoop`, and asserts the restored next action and active state.

- [ ] **Step 2: Add the complete Increment 2 gate**

`Scripts/verify-increment-2.sh` runs all tests and release build, builds and signs the DMG, runs the packaged recovery diagnostic in a temporary vault/Keychain service, scans the full data directory for every distinctive plaintext packet string, reruns capture latency and hot-key checks, mounts the DMG, and verifies the app plus Applications link.

- [ ] **Step 3: Document the delivered behavior and decision**

Update the README usage with Command-Shift-Space, Now focus controls, interruption capture, and Return recovery. Add a decision recording one durable focus session per intention, with interrupted sessions retained independently and lifecycle pairs persisted atomically.

- [ ] **Step 4: Self-review the implementation**

Run placeholder scan (`TODO|FIXME|stub|placeholder`), review the diff for accidental plaintext/logging and unrelated changes, confirm all plan checkboxes match reality, and run the full Increment 2 gate from a clean process state.

- [ ] **Step 5: Request independent code review and resolve findings**

Review against the Increment 2 exit gate, repository compatibility, focus invariants, UI behavior, encryption, and verification evidence. Resolve every blocking finding and rerun affected checks.

- [ ] **Step 6: Commit final verification**

Commit: `test: verify interruption recovery across relaunch`.

Expected final evidence: all tests pass; release build and ad-hoc signature pass; packaged diagnostic reports exact packet recovery; vault scan finds no packet plaintext; capture p95 remains within Increment 1 budgets; hot-key registration passes; DMG mounts with the signed app and Applications link.
