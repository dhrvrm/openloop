# Private Context Trail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an explicit opt-in, focus-session-bound application context trail that improves interruption recovery and gives the Now/Return GUI a clear visual account of where attention moved, while Private Mode remains the default hard stop.

**Architecture:** `ADHDCore` owns privacy settings, bounded application observations, deterministic episode segmentation, retention, and Return-reference composition. The existing repository adapters persist settings and events only inside their snapshots, including the AES-GCM vault. `OpenLoopApp` observes application activation through `NSWorkspace` only while the stored mode is enabled and an active focus exists; `AppModel` exposes the trail to a flat SwiftUI flow inside Now and the menu-bar Private Mode control.

**Tech Stack:** Swift 6.2, Swift Package Manager, Swift Testing, SwiftUI, AppKit `NSWorkspace`, existing AES-GCM vault.

---

## Constraints

- Private Mode is the default for legacy and new stores. It prevents writes immediately and remains visible in the menu and Now surface.
- Opt-in collection records only normalized application bundle identifier, readable application name, focus/intention/session IDs, and observation time.
- Never record window titles, document names, typed text, URLs, clipboard, microphone, system audio, location, keystrokes, or screenshots.
- Observe only while a focus session is `.active`; paused, interrupted, finished, or absent focus produces no event.
- Consecutive observations of the same bundle identifier merge into one episode. Retain at most eight hours and 100 observations per focus session.
- Ambient observations never create captures, memories, tasks, notifications, or obligations.
- Return packets receive one inspectable `Context trail — App A → App B` reference when evidence exists; manual interruption fields remain authoritative.
- Existing stores decode with private mode and no events. Vault files must not expose application names or bundle identifiers as plaintext.
- Keep the five-surface product boundary. Add the trail to Now and existing Return references; do not add a settings screen.
- Apply targeted native visual improvements only: clearer hierarchy, restrained warm-neutral surfaces, a horizontal node-and-arrow trail, complete empty/loading/error/private states, and no dashboard totals.
- Focused tests only. Do not run the complete verification or DMG suite.
- Do not create `SUBSYSTEM.md` files or invoke a `designer` agent.

## File map

- Create `Sources/ADHDCore/ContextTrail.swift`: values, provider seams, segmentation, retention, recording loop, Return reference provider, fixture report.
- Modify `Sources/ADHDCore/Ports.swift`: compatible settings/event persistence methods.
- Modify `Sources/LocalStore/JSONFileThoughtRepository.swift`: legacy-safe local snapshot fields and bounded event replacement.
- Modify `Sources/VaultStore/EncryptedThoughtRepository.swift`: encrypted settings/events and emptiness guards.
- Create `Tests/ADHDCoreTests/ContextTrailTests.swift`: privacy gate, focus gate, segmentation, retention, reference behavior, fixture metrics.
- Modify repository test files: restart, legacy, replacement, and plaintext scanning.
- Modify `Sources/OpenLoopApp/AppModel.swift`: published mode/episodes, opt-in command, observation handling, and failure containment.
- Create `Sources/OpenLoopApp/ApplicationContextObserver.swift`: notification adapter with no persistence or policy logic.
- Modify `Sources/OpenLoopApp/OpenLoopApp.swift`: production wiring, lifecycle, menu state/action, fixture diagnostic.
- Modify `Sources/OpenLoopApp/MainWindowController.swift`: Now context-flow graph and polished privacy/empty states.
- Create `Tests/OpenLoopAppTests/AppModelContextTrailTests.swift` and `ApplicationContextObserverTests.swift`.
- Create `Tests/Fixtures/context-trail-evaluation.json`; modify `README.md`, `docs/DECISIONS.md`, and `Resources/Info.plist` for 0.7.0.

### Task 1: Define private, bounded context evidence

- [x] Add `ContextCollectionMode`, `ContextTrailSettings`, `ContextTrailEvent`, `ContextEpisode`, and `ContextTrailError` with validation that rejects empty identity fields and clamps retention to 1–8 hours.
- [x] Define `ContextTrailProviding` and implement deterministic `ContextTrailPolicy.episodes(from:through:)` that sorts observations, removes events outside retention, caps the newest 100 per session, and merges consecutive matching bundle identifiers.
- [x] Write tests proving the same app merges, A→B→A remains three episodes, out-of-window observations disappear, and malformed identities cannot enter the trail.
- [x] Run `Scripts/test.sh --filter ContextTrailTests` and commit `feat: model private focus context trails`.

```swift
public protocol ContextTrailProviding: Sendable {
    func settings() async throws -> ContextTrailSettings
    func setEnabled(_ enabled: Bool) async throws -> ContextTrailSettings
    func observe(_ application: ApplicationContext, at date: Date) async throws -> ContextTrailEvent?
    func currentEpisodes(at date: Date) async throws -> [ContextEpisode]
}
```

### Task 2: Persist settings and evidence inside existing stores

- [x] Add safe protocol defaults for `save(contextTrailSettings:)`, `contextTrailSettings()`, `append(contextTrailEvent:)`, `contextTrailEvents()`, and `replace(contextTrailEvents:)`; unsupported writes throw `.contextTrailUnsupported`, reads return private/empty.
- [x] Add settings and `[UUID: ContextTrailEvent]` to local/vault snapshots using `decodeIfPresent`; stable reads order by observation time then UUID and replacement writes the bounded complete set atomically.
- [x] Include context events/settings in vault non-empty guards without changing authenticated data or development migration semantics.
- [x] Test local/vault restart and legacy decode. Scan every vault-side file for a distinctive application name and bundle identifier.
- [x] Run `Scripts/test.sh --filter 'contextTrail|ContextTrail'` and commit `feat: persist encrypted context trail evidence`.

### Task 3: Gate recording and enrich Return packets

- [ ] Implement `ContextTrailLoop`: check `.focusTrail`, select only the active focus session, ignore a consecutive duplicate bundle, append the event, then replace the pruned/capped set.
- [ ] Make `setEnabled(false)` immediately persist `.privateMode` and erase retained context events; this is a recoverable privacy action, not a background cleanup promise.
- [ ] Implement `ContextTrailReferenceProvider` over the repository. It returns no reference in private mode/no evidence and otherwise emits one bounded, chronological `Context trail — Xcode → Safari` string for the current session.
- [ ] Compose the existing explicit frontmost reference with the context-trail provider using a small `CompositeContextReferenceProvider` so manual interruption behavior remains intact.
- [ ] Test private/paused/no-focus rejection, enabled active recording, disabling erasure, stable reference order, and manual references surviving provider failure.
- [ ] Run `Scripts/test.sh --filter 'ContextTrailTests|InterruptionSnapshotTests|FocusLoopTests'` and commit `feat: attach opt-in context evidence to return packets`.

### Task 4: Connect explicit runtime observation without background policy leaks

- [ ] Add `ApplicationContextObserver` that converts `NSWorkspace.didActivateApplicationNotification` into `ApplicationContext`, ignores OpenLoop itself/incomplete identities, and calls one async handler. It stores nothing and owns no enablement decision.
- [ ] Inject `ContextTrailProviding` into `AppModel`; publish `contextTrailSettings`, `contextEpisodes`, `isUpdatingContextTrail`, and `contextTrailError`.
- [ ] Add `setContextTrailEnabled(_:)`, `observeApplication(_:)`, and `refreshContextTrail()`; preserve prior episodes on read failure and keep capture/focus/recall errors independent.
- [ ] Refresh the trail after focus start/pause/continue/interruption/finish, and record the known current application immediately after explicit enablement or focus start.
- [ ] Wire the observer only after the model and menu exist; retain/remove the notification token with app lifetime.
- [ ] Test no call before notification, identity filtering, model opt-in/opt-out, failure containment, and observation without a focus producing no episode.
- [ ] Run `Scripts/test.sh --filter 'AppModelContextTrailTests|ApplicationContextObserverTests'` and commit `feat: observe application context only during opted-in focus`.

### Task 5: Make context and privacy legible in the existing GUI

- [ ] Replace the disabled menu label with an actionable item: `Private Mode — on` when disabled and `Focus Context — on` when enabled; state updates whenever the menu opens.
- [ ] Add a restrained privacy line to Now describing exactly `Application names only · active focus only · 8-hour maximum` and a native toggle disabled only during a persistence command.
- [ ] Render episodes as a horizontally scrolling node-and-arrow flow: application name, relative start/end, and observation count. Use system typography, one desaturated accent, tight inner radii, and no nested card stack.
- [ ] Provide explicit states: private (“Nothing is observed”), enabled/no focus (“Start focus to begin”), enabled/empty (“Waiting for an app switch”), and inline failure (“Trail paused; focus remains safe”).
- [ ] Keep Return presentation flat; context-trail references already appear under References with selectable text.
- [ ] Test Recall/Now navigation remains intact, menu toggling calls the model, and the real window can render private plus enabled-empty states.
- [ ] Run `Scripts/test.sh --filter 'AppModelContextTrailTests|MainWindowControllerTests'` and commit `feat: show a private context flow in now`.

### Task 6: Add fixture quality evidence and document the boundary

- [ ] Add `ContextTrailEvaluationReport` with accepted event count, episode compression ratio, false-event rate, and Return-reference coverage; empty denominators return nil.
- [ ] Add `Tests/Fixtures/context-trail-evaluation.json` and `--context-trail-evaluation` output prefixed `context-trail-fixture-`.
- [ ] Document opt-in/default-private behavior, exact collected fields, immediate erasure, retention, Return integration, and exclusions. Record D-019 and bump the bundle to 0.7.0.
- [ ] Mark this plan complete and run only:

```bash
Scripts/test.sh --filter 'ContextTrailTests|contextTrail|AppModelContextTrailTests|ApplicationContextObserverTests|InterruptionSnapshotTests'
```

- [ ] Build/sign the app bundle, relaunch it, confirm version/process, and commit `feat: complete private context trail`.

Expected focused evidence: private mode writes nothing; only active focus accepts observations; app identity is the entire payload; duplicates compress deterministically; disabling erases retained evidence; Return receives a bounded chronological trail; vault files reveal no identity plaintext; failure cannot block capture or focus; and the GUI explains every state without a new screen.
