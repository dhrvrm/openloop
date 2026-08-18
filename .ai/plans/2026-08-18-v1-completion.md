# OpenLoop v1 Completion Plan

**Goal:** Complete the four remaining product increments as one coherent, calm macOS v1 without adding accounts, cloud dependencies, notification debt, or a sixth workspace surface.

**Architecture:** Keep the existing encrypted repository and five-surface product model. Add small domain contracts for ordering and privacy maintenance, expose them through `AppModel`, and rebuild the workspace navigation around a persistent sidebar plus focused content. Release reliability stays headless and scriptable; the application is not launched during implementation.

**Tech stack:** Swift 6.2, SwiftUI/AppKit, CryptoKit, Swift Testing, zsh packaging scripts.

---

## Increment 9 — Orientation and workspace UX

- [ ] Replace the ambiguous text-only tab shell with a clear sidebar workspace for Now, Return, Later, and Recall while retaining Quick Capture as the instant fifth surface.
- [ ] Add an inline Quick Add field to Now and display the typed and voice shortcuts in-context.
- [ ] Make empty states instructional and calm: explain where a capture goes and what the next choice is.
- [ ] Show a ready queue when nothing is actively focused so the user chooses the next move instead of the app implying one.
- [ ] Add focused UI/model tests for navigation, quick add, and empty-state presentation contracts.

## Increment 10 — Complete task lifecycle

- [ ] Add backward-compatible persistent manual ordering to intentions and repository batch persistence.
- [ ] Add domain commands for reorder, direct finish, and release while preserving focus-session invariants.
- [ ] Expose edit/start/finish/release/reorder from the ready queue and Later review rows with compact controls.
- [ ] Keep editing inline and prevent mutation of active/interrupted wording outside existing safe flows.
- [ ] Add focused core, repository, and AppModel lifecycle tests.

## Increment 11 — Privacy and data control

- [ ] Add retention policy, local storage summary, terminal-record pruning, and full reset as repository capabilities.
- [ ] Add same-Mac encrypted vault backup; never export plaintext or copy the root key.
- [ ] Discard the derived Recall index after retention or reset so it rebuilds only from retained evidence.
- [ ] Add a compact Privacy & Storage disclosure to Recall, including explicit backup limitations and destructive confirmations.
- [ ] Add focused vault tests for summary, retention cascade, backup ciphertext, and reset.

## Increment 12 — Release reliability

- [ ] Add calm launch-recovery state and capability visibility for Quick Capture, microphone, and speech recognition.
- [ ] Keep permission requests action-driven and ensure unavailable capabilities do not block typed capture.
- [ ] Make local and stable-signed packaging explicit: ad-hoc builds use the local development key path; release builds require a configured signing identity.
- [ ] Add a headless release verification script for version, signature, local/release flags, and bundle structure.
- [ ] Update product/version documentation to 1.0 and build a closed signed bundle without opening it.

## Dedicated UI/UX track (applies to all increments)

- [ ] Use one hierarchy across all surfaces: eyebrow, title, one-sentence orientation, primary action, then quiet evidence.
- [ ] Use semantic system colors, restrained corner radii, no gradients, no nested card stacks, and no urgency colors or scores.
- [ ] Keep primary actions explicit and keyboard hints visible; move rare/destructive actions behind menus or confirmations.
- [ ] Verify layout structurally with SwiftUI/AppKit tests and compilation only; do not launch or repeatedly activate the application.

## Focused exit gate

- [ ] Run the new v1 test filter once, fix concrete failures, then build and inspect the closed app bundle once.
- [ ] Do not enter broad repetitive verification loops and do not open the app.
