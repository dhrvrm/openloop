# Review & Correct Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every stored capture a calm, inline human review path that can correct its disposition and smallest next action without losing the original evidence.

**Architecture:** Add a core clarification-correction command and append-only correction value, persist the corrected proposal, compatible intention state, and correction atomically in both local repositories, then project a unified review read model into AppModel. Upgrade the existing Later surface with an inline editor; do not add a sixth screen, ambient capture, model dependency, or `SUBSYSTEM.md`.

**Tech Stack:** Swift 6.2, Swift Concurrency, SwiftUI/AppKit, Swift Testing, Codable snapshots, AES-GCM encrypted local vault.

---

### Task 1: Model a valid human clarification correction

**Files:**
- Modify: `Sources/ADHDCore/Clarification.swift`
- Modify: `Sources/ADHDCore/ThoughtLoop.swift`
- Modify: `Sources/ADHDCore/Ports.swift`
- Test: `Tests/ADHDCoreTests/ThoughtLoopTests.swift`

- [x] **Step 1: Write the failing correction transition test**

Add a test that captures an automatically proposed action, reviews it as memory, and asserts that the existing open intention becomes released while the corrected proposal is memory and the correction retains the previous action proposal.

```swift
@Test func humanReviewReclassifiesAnOpenActionWithoutLosingHistory() async throws {
    let repository = MemoryRepository()
    let loop = ThoughtLoop(repository: repository, clarifier: FixedClarifier())
    let result = try await loop.capture(text: "Riya prefers email", at: .now)

    let review = try await loop.review(
        captureID: result.capture.id,
        disposition: .memory,
        desiredOutcome: nil,
        nextAction: nil,
        at: Date(timeIntervalSince1970: 50)
    )

    #expect(review.proposal.disposition == .memory)
    #expect(review.previousProposal?.disposition == .action)
    #expect(try await repository.intention(id: result.capture.id)?.state == .released)
}
```

- [x] **Step 2: Run the focused test and confirm RED**

Run: `Scripts/test.sh --filter humanReviewReclassifiesAnOpenActionWithoutLosingHistory`

Expected: compilation fails because `ThoughtLoop.review` and the correction result do not exist.

- [x] **Step 3: Add the correction values and review command**

Define `ClarificationCorrection` with a stable ID, capture ID, review date, optional previous proposal, and corrected proposal. Add compatible repository defaults for capture lookup and correction application. Add `ThoughtLoop.review(...)` that validates a human-confidence proposal, creates or revises an open action intention, releases an open intention for non-action dispositions, rejects changes to active/interrupted/terminal intentions, and asks the repository to persist the coupled result.

```swift
public struct ClarificationCorrection: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let captureID: UUID
    public let reviewedAt: Date
    public let previousProposal: ClarificationProposal?
    public let proposal: ClarificationProposal
}
```

- [x] **Step 4: Run the focused test and confirm GREEN**

Run: `Scripts/test.sh --filter humanReviewReclassifiesAnOpenActionWithoutLosingHistory`

Expected: one test passes.

- [x] **Step 5: Commit the core transition**

```bash
git add Sources/ADHDCore/Clarification.swift Sources/ADHDCore/ThoughtLoop.swift Sources/ADHDCore/Ports.swift Tests/ADHDCoreTests/ThoughtLoopTests.swift
git commit -m "feat: add human clarification review"
```

### Task 2: Persist corrections atomically and compatibly

**Files:**
- Modify: `Sources/ADHDCore/Ports.swift`
- Modify: `Sources/LocalStore/JSONFileThoughtRepository.swift`
- Modify: `Sources/LocalStore/DevelopmentStoreSnapshot.swift`
- Modify: `Sources/VaultStore/EncryptedThoughtRepository.swift`
- Test: `Tests/LocalStoreTests/JSONFileThoughtRepositoryTests.swift`
- Test: `Tests/VaultStoreTests/EncryptedThoughtRepositoryTests.swift`

- [x] **Step 1: Write focused persistence tests**

For each concrete repository, save a capture and action proposal/intention, apply a memory correction, reopen the repository, and assert the corrected proposal, released intention, and append-only correction all survive. Retain decode compatibility for snapshots without the new collection.

- [x] **Step 2: Run the persistence filter and confirm RED**

Run: `Scripts/test.sh --filter clarificationCorrection`

Expected: compilation fails because repository correction APIs and snapshot storage do not exist.

- [x] **Step 3: Add repository APIs and atomic adapters**

Override the compatible repository seam in the concrete JSON and encrypted stores so proposal, intention, and correction are written in one locked snapshot update; their custom decoders default a missing corrections field to an empty dictionary.

```swift
func apply(
    clarificationCorrection: ClarificationCorrection,
    intention: Intention?
) async throws
func clarificationCorrections(captureID: UUID?) async throws -> [ClarificationCorrection]
func capture(id: UUID) async throws -> RawCapture?
```

- [x] **Step 4: Run the persistence filter and confirm GREEN**

Run: `Scripts/test.sh --filter clarificationCorrection`

Expected: the local and encrypted round-trip tests pass.

- [x] **Step 5: Commit durable review history**

```bash
git add Sources/ADHDCore/Ports.swift Sources/LocalStore Sources/VaultStore Tests/LocalStoreTests Tests/VaultStoreTests
git commit -m "feat: persist clarification corrections"
```

### Task 3: Project a unified review queue

**Files:**
- Modify: `Sources/ADHDCore/ReadModels.swift`
- Modify: `Sources/OpenLoopApp/AppModel.swift`
- Test: `Tests/ADHDCoreTests/ReadModelsTests.swift`
- Test: `Tests/OpenLoopAppTests/AppModelReviewTests.swift`

- [x] **Step 1: Write failing read-model and command tests**

Assert that the review projection includes original capture text, current proposal fields, whether the classifier has made a decision, and the linked intention state. Assert that AppModel applies a corrected action and refreshes Later/open loops, while a validation failure leaves the item present with calm inline error copy.

- [x] **Step 2: Run the focused application filter and confirm RED**

Run: `Scripts/test.sh --filter 'reviewQueue|AppModelReview'`

Expected: compilation fails because the review projection and AppModel command do not exist.

- [x] **Step 3: Add the review projection and application command**

Add `ClarificationReviewItem` and `ThoughtReadModels.reviewQueue()`. AppModel publishes that queue, refreshes it alongside existing projections, and exposes one guarded `applyClarificationReview(...)` command with specific validation and persistence-safe failure messages.

- [x] **Step 4: Run the focused application filter and confirm GREEN**

Run: `Scripts/test.sh --filter 'reviewQueue|AppModelReview'`

Expected: the focused core/application tests pass.

- [x] **Step 5: Commit the review projection**

```bash
git add Sources/ADHDCore/ReadModels.swift Sources/OpenLoopApp/AppModel.swift Tests/ADHDCoreTests/ReadModelsTests.swift Tests/OpenLoopAppTests/AppModelReviewTests.swift
git commit -m "feat: expose capture review queue"
```

### Task 4: Redesign Later as a calm decision surface

**Files:**
- Modify: `Sources/OpenLoopApp/MainWindowController.swift`
- Modify: `Tests/OpenLoopAppTests/MainWindowControllerTests.swift`

- [ ] **Step 1: Add a focused real-window smoke test**

Create a fixture with one unclear capture, show tab 2 in a real window, and assert the Later surface is visible and the model exposes the review item. This guards integration without brittle pixel assertions.

- [ ] **Step 2: Implement the existing-screen redesign**

Replace the generic List with a spacious Later header and two quiet groups: “Needs a decision” and “Held safely.” Render capture text as primary evidence, use plain-language labels instead of raw enum values, and add an inline `ClarificationReviewRow` editor. The editor uses a compact menu for disposition, conditionally reveals outcome/action fields for actions, validates before save, supplies Cancel/Save controls, and never opens a modal.

- [ ] **Step 3: Run the focused GUI test**

Run: `Scripts/test.sh --filter 'laterWindow|AppModelReview'`

Expected: the real-window smoke and AppModel review tests pass.

- [ ] **Step 4: Commit the Later experience**

```bash
git add Sources/OpenLoopApp/MainWindowController.swift Tests/OpenLoopAppTests/MainWindowControllerTests.swift
git commit -m "feat: make Later a review surface"
```

### Task 5: Document and package Increment 8

**Files:**
- Modify: `docs/INCREMENTS.md`
- Modify: `docs/DECISIONS.md`
- Modify: `docs/DATA.md`
- Modify: `Resources/Info.plist`
- Modify: `.ai/plans/2026-08-18-review-and-correct.md`

- [ ] **Step 1: Record the product boundary**

Document Increment 8 as human clarification review, decision D-020 as append-only local correction evidence, and the correction record in the vault data inventory. State that review cannot silently rewrite an active or interrupted focus and that the original raw capture remains immutable.

- [ ] **Step 2: Set the application version to 0.8.0**

Update `CFBundleShortVersionString` from `0.7.0` to `0.8.0` without changing the bundle identifier.

- [ ] **Step 3: Run one focused acceptance pass**

Run: `Scripts/test.sh --filter 'humanReview|clarificationCorrection|reviewQueue|AppModelReview|laterWindow'`

Expected: all Increment 8 focused tests pass with zero failures.

- [ ] **Step 4: Build, sign, and launch the application bundle**

Run: `Scripts/build-app.sh`, terminate only the currently running Increment 7 bundle if present, then `open '.artifacts/app/OpenLoop ADHD.app'`.

Expected: the release arm64 bundle builds, ad-hoc signature verification succeeds, and the 0.8.0 GUI launches.

- [ ] **Step 5: Mark the plan complete and commit the increment**

```bash
git add .ai/plans/2026-08-18-review-and-correct.md docs Resources/Info.plist
git commit -m "feat: complete review and correct"
```
