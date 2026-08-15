# Visible Contextual Resurfacing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make OpenLoop launch as an immediately visible macOS workspace, expose every stored open loop, and resurface at most two relevant intentions from explicit local application context with a deterministic, inspectable explanation and one-action suppression.

**Architecture:** `ADHDCore` owns context values, explicit intention-context rules, suggestion history, deterministic relevance scoring, cooldown policy, and the resurfacing orchestration loop. `ThoughtRepository` gains backward-compatible context-rule and suggestion-history persistence, with atomic encrypted production writes where a suggestion and its history must stay aligned. `OpenLoopApp` remains a native SwiftUI/AppKit application: it becomes a regular Dock app, opens the main window on launch/reopen, observes only an on-demand frontmost-app snapshot, and renders a calm suggestion panel plus a native signal graph. The five product surfaces remain Capture, Now, Return, Later, and Recall; Increment 3 adds resurfacing to Now and stored open loops to Later rather than inventing another screen.

**Tech Stack:** Swift 6.2, Swift Package Manager, Swift Testing, SwiftUI, AppKit/NSWorkspace, CryptoKit AES-GCM, Security Keychain Services, zsh packaging diagnostics.

---

## Constraints

- Preserve Increment 0–2 capture, clarification, focus, interruption, Return, encrypted storage, migration, and latency behavior.
- Launch as a regular foreground application with a Dock icon and an on-screen main window. Keep the menu-bar entry and global capture shortcut.
- Do not require the user to discover a menu-bar icon before seeing their data. Dock reopen must restore the workspace.
- Show all non-closed, non-released intentions in Later's open-loop library; do not duplicate the current or interrupted item there without visibly identifying its state.
- Suggestions are local, explainable, and triggered by an on-demand context snapshot when the workspace appears. Do not add background monitoring, notifications, accounts, network access, telemetry, Accessibility, or Automation permissions.
- A suggestion requires an explicit user-authored application link. No title/content surveillance and no inferred semantic profile.
- Use a deterministic score with named contributions. An application match contributes `1.0`; the eligibility threshold is `1.0`. Sort ties by oldest intention creation date then UUID and return at most two suggestions.
- Rate-limit per intention: a shown suggestion enters a four-hour cooldown. `Later` suppresses it for one day. `Never` suppresses it permanently. Each control is one action and survives relaunch.
- Every displayed suggestion states why it appeared. The signal graph is a native, accessible horizontal contribution bar—not a decorative chart library or an opaque model visualization.
- Never introduce overdue labels, streaks, badges, backlog counts, urgency scores, guilt language, or notification debt.
- Keep existing vault authenticated data unchanged so schema-1 data remains decryptable. New snapshot fields decode as empty when absent, and new context strings must never appear in plaintext vault files.
- Do not create or invoke a `designer` agent. Do not add a formal `SUBSYSTEM.md` graph.

## File map

- `Sources/ADHDCore/Resurfacing.swift`: context, rule, history, feedback, score explanation, policy, and orchestration types.
- `Sources/ADHDCore/Ports.swift`: compatible rule/history persistence contract.
- `Sources/ADHDCore/ReadModels.swift`: stored open-loop library projection.
- `Sources/LocalStore/JSONFileThoughtRepository.swift`: development rule/history persistence.
- `Sources/VaultStore/EncryptedThoughtRepository.swift`: encrypted rule/history persistence and atomic suggestion recording.
- `Sources/OpenLoopApp/FrontmostApplicationReferenceProvider.swift`: structured on-demand foreground application context.
- `Sources/OpenLoopApp/AppModel.swift`: library, context-linking, suggestion refresh, and feedback commands.
- `Sources/OpenLoopApp/MainWindowController.swift`: visible workspace, suggestion panel, contribution graph, and open-loop library.
- `Sources/OpenLoopApp/OpenLoopApp.swift`: foreground lifecycle, launch/reopen behavior, production wiring, and packaged diagnostics.
- `Resources/Info.plist`: regular-app policy and Increment 3 version.
- `Scripts/verify-increment-3.sh`: full Increment 3 exit gate.
- `README.md`, `docs/DECISIONS.md`: user behavior and architecture decision.

### Task 1: Make the native workspace visible on launch and reopen

**Files:**
- Modify: `Sources/OpenLoopApp/MainWindowController.swift`
- Modify: `Sources/OpenLoopApp/OpenLoopApp.swift`
- Modify: `Resources/Info.plist`
- Create: `Tests/OpenLoopAppTests/MainWindowControllerTests.swift`

- [ ] **Step 1: Write a failing lifecycle seam test**

Expose read-only window state needed by tests and verify `show(tab:)` selects the requested surface and orders a titled window on screen. Add a delegate lifecycle test seam that proves initial startup and Dock reopen request the main workspace.

- [ ] **Step 2: Verify focused failure**

Run `Scripts/test.sh --filter MainWindowControllerTests`.

Expected: compilation or assertions fail because lifecycle/window observability and reopen behavior do not exist.

- [ ] **Step 3: Implement regular foreground lifecycle**

Use `.regular` activation, remove `LSUIElement`, bump the bundle version to `0.3.0`, show Now after successful startup, and implement `applicationShouldHandleReopen(_:hasVisibleWindows:)` to restore Now when no window is visible. Preserve menu-bar actions and Quick Capture.

- [ ] **Step 4: Add a packaged window diagnostic**

Add `--window-test`, which constructs the production window, shows it, waits one run-loop turn, verifies it is visible/key with a valid window number, prints `window-test=passed`, and exits nonzero on failure.

- [ ] **Step 5: Run tests and commit**

Run `Scripts/test.sh --filter OpenLoopAppTests && swift build -c release`.

Commit: `fix: open a visible workspace on launch`.

### Task 2: Expose every stored open loop in Later

**Files:**
- Modify: `Sources/ADHDCore/ReadModels.swift`
- Modify: `Tests/ADHDCoreTests/ReadModelsTests.swift`
- Modify: `Sources/OpenLoopApp/AppModel.swift`
- Modify: `Sources/OpenLoopApp/MainWindowController.swift`

- [ ] **Step 1: Write failing library projection tests**

Add `OpenLoopItem` and verify the projection contains open, active, and interrupted intentions with desired outcome, next action, state, and creation time; excludes closed/released intentions; and orders current/active before open before interrupted, with stable date/UUID ties.

- [ ] **Step 2: Implement the read model and app publication**

Add `ThoughtReadModels.openLoops()` and publish it from `AppModel.refresh()` alongside Now, Return, and Later without changing their existing semantics.

- [ ] **Step 3: Render a calm Later library**

Keep the Later tab. Show `Open loops` first with outcome, exact next action, and a neutral state label, followed by `Notes and captures`. Empty-state text distinguishes a truly empty store from a store containing only one category.

- [ ] **Step 4: Run tests and commit**

Run `Scripts/test.sh --filter 'ReadModelsTests|OpenLoopAppTests' && Scripts/test.sh`.

Commit: `feat: expose stored open loops in Later`.

### Task 3: Define deterministic, explainable resurfacing

**Files:**
- Create: `Sources/ADHDCore/Resurfacing.swift`
- Create: `Tests/ADHDCoreTests/ResurfacingTests.swift`

- [ ] **Step 1: Write failing value and scoring tests**

Cover normalized application bundle identifiers/names; a rule linked to one intention; a matching and nonmatching `ContextEvent`; exact `RelevanceContribution` label/value/explanation; threshold behavior; stable tie ordering; maximum-two selection; and the absence of recency/age penalties.

- [ ] **Step 2: Write failing cooldown and suppression tests**

Cover first eligibility, four-hour shown cooldown, eligibility at the boundary, one-day `Later`, permanent `Never`, and unrelated intentions remaining eligible. All decisions use an injected date.

- [ ] **Step 3: Implement pure domain types and scorer**

Create Codable/Sendable/Equatable context, rule, history-event, feedback, contribution, and suggestion values. Implement a pure `RelevanceScorer` and `ResurfacingPolicy` with the constants in Constraints. Keep reason text derived from the public contribution values so UI explanations cannot drift from scoring.

- [ ] **Step 4: Run tests and commit**

Run `Scripts/test.sh --filter ResurfacingTests && Scripts/test.sh --filter ADHDCoreTests`.

Commit: `feat: score explicit context with explainable relevance`.

### Task 4: Persist context rules and suggestion history safely

**Files:**
- Modify: `Sources/ADHDCore/Ports.swift`
- Modify: `Sources/LocalStore/JSONFileThoughtRepository.swift`
- Modify: `Sources/VaultStore/EncryptedThoughtRepository.swift`
- Modify: `Tests/LocalStoreTests/JSONFileThoughtRepositoryTests.swift`
- Modify: `Tests/VaultStoreTests/EncryptedThoughtRepositoryTests.swift`

- [ ] **Step 1: Write failing repository contract tests**

For both adapters, save/update/delete a rule, append ordered history, reopen, and compare exact values. Verify an Increment 2 snapshot without the new fields still opens. For the vault, scan the complete directory and prove distinctive application names, bundle identifiers, reason text, and feedback values are absent as plaintext.

- [ ] **Step 2: Extend the port compatibly**

Add `save(resurfacingRule:)`, `deleteResurfacingRule(intentionID:)`, `resurfacingRules()`, `append(suggestionEvent:)`, and `suggestionEvents()` with compatibility defaults. Add one production atomic operation to record a shown suggestion event together with any rule update required by feedback.

- [ ] **Step 3: Add backward-compatible snapshot fields**

Store rules by intention ID and events by event ID in both adapters. Custom decoding defaults missing fields to empty. Keep stable event ordering by timestamp then UUID and do not change the vault authenticated-data string.

- [ ] **Step 4: Run tests and commit**

Run `Scripts/test.sh --filter 'LocalStoreTests|VaultStoreTests' && Scripts/test.sh`.

Commit: `feat: persist encrypted resurfacing preferences and history`.

### Task 5: Orchestrate suggestions and feedback

**Files:**
- Modify: `Sources/ADHDCore/Resurfacing.swift`
- Modify: `Sources/ADHDCore/Ports.swift`
- Modify: `Tests/ADHDCoreTests/ResurfacingTests.swift`

- [ ] **Step 1: Write failing orchestration tests**

Using an in-memory repository, verify `suggest(for:at:)` loads only open intentions and explicit rules, applies cooldown/suppression, emits at most two stable suggestions, and records a shown event. Verify repeated evaluation inside cooldown is empty.

- [ ] **Step 2: Write failing feedback tests**

Verify `start`, `later`, and `never` record feedback. `later` suppresses exactly one day, `never` is permanent, and feedback for a missing/non-open intention returns a typed error without partial writes.

- [ ] **Step 3: Implement `ResurfacingLoop`**

Inject repository, scorer, and policy. Keep time and context explicit in every method. Return domain suggestions already containing the user-facing explanation/contributions needed by the UI.

- [ ] **Step 4: Run tests and commit**

Run `Scripts/test.sh --filter ResurfacingTests && Scripts/test.sh --filter ADHDCoreTests`.

Commit: `feat: orchestrate rate-limited contextual suggestions`.

### Task 6: Capture structured application context on demand

**Files:**
- Modify: `Sources/OpenLoopApp/FrontmostApplicationReferenceProvider.swift`
- Modify: `Tests/OpenLoopAppTests/FrontmostApplicationReferenceProviderTests.swift`
- Modify: `Sources/OpenLoopApp/OpenLoopApp.swift`

- [ ] **Step 1: Write failing adapter tests**

Inject a lookup that returns bundle ID and localized name. Verify normalized `ApplicationContext`, nil for incomplete/absent applications, and continued readable interruption references. Verify no permissions or workspace observer are registered.

- [ ] **Step 2: Implement the dual-purpose provider**

Retain `ContextReferenceProvider` behavior for interruption packets and add a structured `currentContext()` method for resurfacing. Production performs one `NSWorkspace.shared.frontmostApplication` lookup only when requested.

- [ ] **Step 3: Wire the resurfacing loop**

Create one provider and one `ResurfacingLoop`. When the workspace is opened by launch, Dock, or Now menu action, snapshot the application that was foreground before OpenLoop activates, refresh suggestions, then show the window.

- [ ] **Step 4: Run tests and commit**

Run `Scripts/test.sh --filter FrontmostApplicationReferenceProviderTests && Scripts/test.sh`.

Commit: `feat: observe foreground context only on demand`.

### Task 7: Build the suggestion panel and native relevance graph

**Files:**
- Modify: `Sources/OpenLoopApp/AppModel.swift`
- Modify: `Sources/OpenLoopApp/MainWindowController.swift`
- Modify: `Tests/OpenLoopAppTests/AppModelResurfacingTests.swift`

- [ ] **Step 1: Write failing app-model tests**

Verify context refresh publishes suggestions; linking an open loop to the current application persists a rule; unlinking removes it; Start begins focus and clears the suggestion; Later and Never apply feedback and immediately remove it; failures keep stored work intact and use neutral error text.

- [ ] **Step 2: Add context controls to the open-loop library**

Each eligible Later row offers `Suggest in <Application>` or `Stop suggesting here` based on the current on-demand context. Make the action explicit; never auto-link from capture text.

- [ ] **Step 3: Add the calm Now suggestion panel**

Place up to two suggestions beneath the current intention or in Now's empty state. Show outcome, exact next action, `Why now: linked to <Application>`, and Start/Later/Never controls. Do not show scores as performance metrics.

- [ ] **Step 4: Render an accessible explanation graph**

For each named contribution, render a labeled native horizontal bar whose width is proportional to contribution/threshold and whose accessibility value states its cause. Display the algorithm summary (`1 explicit match required`, `4-hour cooldown`, `up to 2`) as quiet explanatory text rather than a dashboard.

- [ ] **Step 5: Refine native visual hierarchy**

Use warm system-neutral surfaces, flat section containers, restrained accent color, generous spacing, and native typography. Avoid gradients, heavy shadows, nested cards, tiny text, and decorative analytics. Keep the window usable at 660×540 and accessible under Dynamic Type.

- [ ] **Step 6: Run tests and commit**

Run `Scripts/test.sh --filter OpenLoopAppTests && Scripts/test.sh && swift build -c release`.

Commit: `feat: explain contextual suggestions in the workspace`.

### Task 8: Prove packaged Increment 3 behavior and hand off a running GUI

**Files:**
- Modify: `Sources/OpenLoopApp/OpenLoopApp.swift`
- Create: `Scripts/verify-increment-3.sh`
- Modify: `README.md`
- Modify: `docs/DECISIONS.md`
- Modify: `.ai/plans/2026-08-15-visible-contextual-resurfacing.md`

- [ ] **Step 1: Add a packaged resurfacing diagnostic**

`--resurfacing-test` creates two distinctive open intentions, explicitly links only one to a synthetic application, evaluates it, verifies the exact explanation and one-result selection, evaluates again to prove cooldown, applies Later and Never in separate cases, reopens the encrypted vault, and verifies persisted suppression/history.

- [ ] **Step 2: Add the full Increment 3 gate**

`Scripts/verify-increment-3.sh` runs all tests and a release build; packages and signs the app; runs window, resurfacing, focus-recovery, capture-latency, and hot-key diagnostics in temporary isolated vaults/Keychain services; scans all data for distinctive resurfacing and focus plaintext; mounts the DMG; and verifies the app plus Applications link.

- [ ] **Step 3: Perform visual GUI verification**

Launch the packaged app with isolated seeded diagnostic data, verify an on-screen `OpenLoop ADHD` window via CoreGraphics, capture Now and Later screenshots, and inspect them for clipping, hierarchy, readable explanation bars, stored-loop visibility, and usable controls at the minimum window size.

- [ ] **Step 4: Document delivered behavior and decision**

Update README usage for visible launch, Dock reopen, open-loop library, explicit context linking, Why now, Later, and Never. Record the decision to use explicit application rules plus on-demand context and deterministic scoring instead of ambient/semantic inference.

- [ ] **Step 5: Self-review the implementation**

Run placeholder scan (`TODO|FIXME|stub|placeholder`), inspect the diff for unrelated changes and accidental plaintext/logging, verify every plan checkbox against evidence, and run the full gate from a clean process state.

- [ ] **Step 6: Request independent code review and resolve findings**

Review against the Increment 3 exit gate, foreground lifecycle, suggestion caps/cooldowns, one-action suppression, legacy compatibility, encryption, accessibility, and packaged verification. Resolve every blocking finding and rerun affected checks.

- [ ] **Step 7: Replace the stale running build and show the result**

Resolve the exact old OpenLoop process path, terminate only that stale app instance, launch the new packaged Increment 3 app, and verify its window is on screen. Do not touch user data outside the app's normal vault.

- [ ] **Step 8: Commit final verification**

Commit: `test: verify visible contextual resurfacing`.

Expected final evidence: all tests and release build pass; packaged window diagnostic proves the GUI is visible; only explicitly linked intentions resurface; every suggestion explains its application match; cooldown/Later/Never survive relaunch; vault scans reveal no sensitive plaintext; Increment 1/2 latency, hot-key, focus, and Return gates remain green; inspected screenshots show all stored open loops and readable controls; the signed DMG mounts; and the current Increment 3 app is running with an on-screen workspace.
