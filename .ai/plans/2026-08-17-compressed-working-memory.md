# Compressed Working Memory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Derive a small encrypted temporal ledger of evidence-backed facts, decisions, commitments, preferences, questions, and corrections, preserving supersession and contradiction history and exposing it through Recall.

**Architecture:** `ADHDCore` owns atomic memory values, explicit candidate rules, an extraction-provider contract, evidence validation, semantic-delta merge, and a compiler loop. The existing encrypted vault persists immutable evidence references and versioned memory state; Recall projects every ledger state so newer corrections affect current ranking without deleting history. Compilation is demand-driven when Recall opens and never blocks capture.

**Tech Stack:** Swift 6.2, Swift Package Manager, Swift Testing, SwiftUI, AppKit, CryptoKit AES-GCM, existing encrypted vault and Recall engine.

---

## Constraints

- Preserve all Increment 0–5 behavior and shortcuts. No network, account, telemetry, ambient sensing, notification, or generated answer.
- Candidate extraction requires explicit evidence markers: `remember:`, `decision:`, `commitment:`/`promise:`, `prefer:`/`preference:`, `question:`, and `correction: old -> new`. Unmarked prose produces no memory.
- Transcription corrections produce correction candidates directly from stored recognized/corrected evidence.
- Accepted statements are atomic, non-empty, at most 500 characters, and retain an exact evidence excerpt plus `RecallEvidenceID` and evidence date.
- The validator must find the referenced document and exact excerpt. Missing evidence rejects acceptance. Later source deletion changes availability to `.expired` but retains the ledger claim and excerpt with a visible warning.
- Equivalent kind/statement candidates merge new evidence into the existing record and increment its version. Do not create duplicate active memories.
- Explicit `old -> new` correction supersedes active records whose normalized statement equals `old`. It creates a new correction memory and retains superseded records.
- Contradictory active claims are preserved; no rule silently chooses a winner. Only explicit correction evidence supersedes.
- Confidence is evidence-derived (`1` for explicit markers/corrections), never model probability or fabricated certainty.
- Compilation is idempotent per evidence reference and runs only on Recall activation or an explicit refresh.
- Memory records are stored inside the existing AES-GCM vault snapshot. No plaintext ledger or separate unencrypted cache.
- Keep the Recall UI flat and editorial: current memory first, historical state and evidence availability explicit, no dashboard totals or productivity score.
- Focused tests only; do not run exhaustive verification or DMG gates unless requested.
- Do not create `SUBSYSTEM.md` files or invoke a `designer` agent.

## File map

- `Sources/ADHDCore/WorkingMemory.swift`: values, rules, provider contract, validator, ledger merge, compiler, evaluation.
- `Sources/ADHDCore/Ports.swift`: compatible memory persistence methods.
- `Sources/LocalStore/JSONFileThoughtRepository.swift`: development ledger persistence and stable reads.
- `Sources/VaultStore/EncryptedThoughtRepository.swift`: encrypted ledger persistence and legacy decode.
- `Sources/ADHDCore/Recall.swift`: memory evidence kind, document projection, and current-state ranking.
- `Sources/OpenLoopApp/AppModel.swift`: demand-driven compilation and published current/history state.
- `Sources/OpenLoopApp/MainWindowController.swift`: quiet memory ledger inside Recall.
- `Sources/OpenLoopApp/OpenLoopApp.swift`: production compiler wiring and fixture diagnostic.
- `Tests/ADHDCoreTests/WorkingMemoryTests.swift`: candidates, validation, merge, supersession, contradiction, expiration, idempotence, metrics.
- `Tests/LocalStoreTests/JSONFileThoughtRepositoryTests.swift`: ledger restart/legacy tests.
- `Tests/VaultStoreTests/EncryptedThoughtRepositoryTests.swift`: ledger restart/plaintext tests.
- `Tests/OpenLoopAppTests/AppModelMemoryTests.swift`: demand-driven compilation state.
- `Tests/Fixtures/memory-evaluation.json`: deterministic mixed ledger fixture.
- `README.md`, `docs/DECISIONS.md`, `Resources/Info.plist`: behavior, privacy decision, version 0.6.0.

### Task 1: Define atomic memories and explicit candidate extraction

- [ ] Create `MemoryKind`, `MemoryState`, `EvidenceAvailability`, `MemoryEvidence`, `MemoryRecord`, `MemoryCandidate`, and `MemoryRelation` in `WorkingMemory.swift`.
- [ ] Write `WorkingMemoryTests` proving every accepted prefix maps to the correct kind, unmarked/action prose returns no candidate, 500-character/empty statements are rejected, `correction: old -> new` stores `.supersedes(old)`, and transcription corrections become `.correction` candidates.
- [ ] Define `MemoryExtractionProvider` and implement `DeterministicMemoryExtractionProvider` with exact case-insensitive prefix parsing and no inferred candidate path.
- [ ] Run `Scripts/test.sh --filter WorkingMemoryTests` and commit `feat: extract explicit working memory candidates`.

```swift
public protocol MemoryExtractionProvider: Sendable {
    func candidates(from documents: [RecallDocument]) async throws -> [MemoryCandidate]
}
```

### Task 2: Validate evidence and merge temporal state

- [ ] Write failing tests for exact excerpt validation, missing evidence rejection, equivalent evidence merge/version increment, idempotent evidence, explicit supersession, and unresolved contradiction preservation.
- [ ] Implement `MemoryEvidenceValidator.validate(_:against:)` and `TemporalMemoryLedger.applying(_:to:at:)`.
- [ ] A merge retains one record ID, increments `version`, unions evidence stably, and updates `updatedAt`. Supersession marks matched active records `.superseded(by:newID)` and never removes them.
- [ ] Add `revalidated(against:)` to mark each evidence reference retained/expired and set record `.evidenceExpired` only when no retained evidence remains.
- [ ] Run `Scripts/test.sh --filter WorkingMemoryTests` and commit `feat: preserve temporal memory revisions and evidence`.

### Task 3: Persist the ledger in both repositories

- [ ] Add protocol methods with safe defaults:

```swift
func save(memoryRecords: [MemoryRecord]) async throws
func memoryRecords() async throws -> [MemoryRecord]
```

- [ ] Add `[UUID: MemoryRecord]` to local and vault snapshots using `decodeIfPresent ?? [:]`; save a complete compiler result in one locked/encrypted update and read by `updatedAt`, kind, UUID.
- [ ] Test local restart and legacy snapshots. Test encrypted restart and scan all vault bytes for statement/evidence plaintext.
- [ ] Include memory emptiness in vault guards without changing authenticated data or migration meaning.
- [ ] Run focused repository tests and commit `feat: persist encrypted temporal memory ledger`.

### Task 4: Compile idempotently and connect current memory to Recall

- [ ] Implement `WorkingMemoryCompiler.compile()` using `RecallDocumentSource`, extraction provider, validator, repository ledger, merge, revalidation, and one final atomic save. Skip evidence already attached to any record.
- [ ] Add `.memory` to `RecallEvidenceKind`. `RecallDocumentSource` projects all records: active title by kind, superseded/history labels, stored statement/excerpts, and current state metadata.
- [ ] Update Recall score so active memory is neutral, contradictory history is multiplied by `0.85`, superseded by `0.55`, and expired-evidence memory by `0.4`; results remain searchable and inspectable.
- [ ] Test compiler idempotence, correction changes first current result, and superseded evidence remains queryable.
- [ ] Run `Scripts/test.sh --filter 'WorkingMemoryTests|RecallTests'` and commit `feat: compile evidence-backed memory into recall`.

### Task 5: Render current and historical memory without a new screen

- [ ] Inject `WorkingMemoryCompiling` into `AppModel`; publish `memoryRecords`, `isCompilingMemory`, and `memoryError`. `refreshMemory()` runs on Recall activation, keeps prior records on failure, and does not alter capture/focus errors.
- [ ] Add a compact “Working memory” section above Recall search showing active statements first, kind, state, evidence count, and retained/expired copy. Historical records are disclosed below a native divider.
- [ ] Add “Refresh evidence” as a quiet secondary action. Do not add a global shortcut or sixth surface.
- [ ] Test model failure containment and Recall tab rendering/navigation.
- [ ] Run `Scripts/test.sh --filter 'AppModelMemoryTests|MainWindowControllerTests'` and commit `feat: show evidence-backed working memory in recall`.

### Task 6: Add deterministic quality reporting and document Increment 6

- [ ] Add `MemoryEvaluationReport` for evidence coverage, contradiction preservation, current-state accuracy, and accepted-memory count. Empty input returns nil rates.
- [ ] Add `Tests/Fixtures/memory-evaluation.json` and `--memory-evaluation` stable diagnostic output labeled fixture.
- [ ] Document explicit markers, evidence retention, supersession/history, demand-driven compilation, and the lack of generated claims. Record D-018. Set bundle version 0.6.0.
- [ ] Mark this plan complete and run only:

```bash
Scripts/test.sh --filter 'WorkingMemoryTests|transcriptionMemory|AppModelMemoryTests|RecallTests'
```

- [ ] Commit `feat: complete compressed working memory`.

Expected focused evidence: unmarked prose creates nothing; every accepted record has exact evidence; equivalent evidence merges; explicit corrections supersede without deletion; missing source evidence is visible; the vault exposes no memory plaintext; Recall ranks current corrections ahead of history; compilation is idempotent and capture-independent.
