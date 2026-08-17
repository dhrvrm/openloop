# Personal Recall Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add fast, evidence-first local recall across captures, intentions, return packets, and transcription corrections through exact and semantic retrieval, an encrypted rebuildable index, a visible Recall surface, and one global shortcut.

**Architecture:** `ADHDCore` owns provider-neutral recall documents, scoring, evaluation, and the orchestration loop. `VaultStore` owns an independently encrypted derived index keyed from the vault root; `OpenLoopApp` supplies Apple Natural Language sentence embeddings and the native Recall UI. Source evidence remains authoritative, index contents are disposable, Quick Capture never waits for indexing, and every result exposes its evidence kind and score contributions rather than generating an answer.

**Tech Stack:** Swift 6.2, Swift Package Manager, Swift Testing, SwiftUI, AppKit, Carbon global hot keys, NaturalLanguage `NLEmbedding`, CryptoKit AES-GCM/HKDF, Security Keychain Services.

---

## Constraints

- Preserve typed `Command-Shift-Space`, voice `Command-Shift-R`, visible launch, Now, Return, Later, focus, resurfacing, encrypted vault, and offline operation.
- Add Recall as the fifth allowed product surface and `Command-Shift-F` as its direct shortcut. Do not add a sixth screen, browser UI, account, server, telemetry, or network provider.
- Search raw captures, all intention states, return packets, and transcription corrections. Closed and released work remains recallable evidence.
- Results contain stored evidence only. Do not generate answers, claims, confidence prose, inferred commitments, or hidden summaries.
- Exact retrieval is deterministic and useful without an embedding. Semantic retrieval is additive and may fail quietly while exact results remain available.
- Apple Natural Language is the selected production embedding adapter. Persisted snapshots contain provider-neutral vectors plus a provider identifier, never `NLEmbedding` types.
- The derived index is AES-GCM encrypted with a key derived from the vault root and distinct authenticated data. No plaintext token sidecar, SQLite file, log, or fixture enters the user vault.
- Index synchronization happens on Recall activation/search, never in the Quick Capture save path. A stale or corrupt index is rebuilt from authoritative encrypted evidence.
- Ranking is inspectable: exact phrase, token coverage, and semantic similarity are separate contributions. Stable ties use evidence date, kind, then UUID.
- A fixed evaluation fixture measures top-five evidence recall and exact-query p95. It demonstrates the harness, not personal-corpus acceptance.
- Continue with focused tests only. Do not run exhaustive verification or packaging gates unless the user asks.
- Do not create `SUBSYSTEM.md` files or invoke a `designer` agent.

## File map

- `Sources/ADHDCore/Recall.swift`: evidence values, tokenization, scoring, embedding/index contracts, loop, and evaluation report.
- `Sources/ADHDCore/Ports.swift`: compatible all-evidence repository reads used to build recall documents.
- `Sources/LocalStore/JSONFileThoughtRepository.swift`: stable all-capture/all-intention reads.
- `Sources/VaultStore/EncryptedThoughtRepository.swift`: stable synchronized all-capture/all-intention reads.
- `Sources/VaultStore/EncryptedRecallIndexStore.swift`: derived-key AES-GCM recall snapshot persistence and corruption-as-cache-miss behavior.
- `Sources/OpenLoopApp/NaturalLanguageEmbeddingProvider.swift`: local sentence-vector adapter.
- `Sources/OpenLoopApp/AppModel.swift`: recall query/loading/results/error state.
- `Sources/OpenLoopApp/MainWindowController.swift`: editorial native Recall tab and evidence rows.
- `Sources/OpenLoopApp/OpenLoopApp.swift`: production recall wiring, menu item, hot key, and fixture diagnostic.
- `Package.swift`: link NaturalLanguage for the app target.
- `Tests/ADHDCoreTests/RecallTests.swift`: source projection, exact/semantic rank, stable ties, fallback, and evaluation tests.
- `Tests/VaultStoreTests/EncryptedRecallIndexStoreTests.swift`: restart, plaintext scan, wrong-key, and corrupt-cache tests.
- `Tests/OpenLoopAppTests/AppModelRecallTests.swift`: query state and failure-copy tests.
- `Tests/OpenLoopAppTests/MainWindowControllerTests.swift`: Recall tab selection.
- `Tests/Fixtures/recall-evaluation.json`: mixed evidence/query fixture.
- `README.md`, `docs/DECISIONS.md`, `Resources/Info.plist`: behavior, privacy decision, and version 0.5.0.

### Task 1: Project every authoritative evidence type into recall documents

**Files:**
- Create: `Sources/ADHDCore/Recall.swift`
- Create: `Tests/ADHDCoreTests/RecallTests.swift`
- Modify: `Sources/ADHDCore/Ports.swift`
- Modify: `Sources/LocalStore/JSONFileThoughtRepository.swift`
- Modify: `Sources/VaultStore/EncryptedThoughtRepository.swift`

- [ ] **Step 1: Write failing document-source tests**

Create captures, an open intention, a closed intention with a return packet, and a correction. Assert that `RecallDocumentSource(repository:).documents()` returns `.capture`, `.intention`, `.returnPacket`, and `.correction` documents with stable `RecallEvidenceID(kind:id:)`, exact stored text, dates, and source labels. Assert closed and released intentions are included.

```swift
let documents = try await RecallDocumentSource(repository: repository).documents()
#expect(Set(documents.map(\.evidenceID.kind)) == [.capture, .intention, .returnPacket, .correction])
#expect(documents.contains { $0.text.contains("Exact restart action") })
```

- [ ] **Step 2: Run the focused failure**

Run `Scripts/test.sh --filter RecallTests`.

Expected: compilation fails because `RecallDocumentSource` and recall values do not exist.

- [ ] **Step 3: Add compatible authoritative reads**

Add repository requirements and defaults:

```swift
func allCaptures() async throws -> [RawCapture]
func allIntentions() async throws -> [Intention]
```

Compatibility defaults return `[]`. Both real repositories return every value sorted by creation date then UUID; the encrypted repository synchronizes before reading.

- [ ] **Step 4: Implement document values and source projection**

Define:

```swift
public enum RecallEvidenceKind: String, Codable, CaseIterable, Hashable, Sendable {
    case capture, intention, returnPacket, correction
}

public struct RecallEvidenceID: Codable, Equatable, Hashable, Sendable {
    public let kind: RecallEvidenceKind
    public let id: UUID
}

public struct RecallDocument: Codable, Equatable, Identifiable, Sendable {
    public var id: RecallEvidenceID { evidenceID }
    public let evidenceID: RecallEvidenceID
    public let title: String
    public let text: String
    public let occurredAt: Date
}
```

`RecallDocumentSource` produces one capture document, one intention document combining desired outcome/next action/state, an additional return-packet document when present, and one correction document combining corrected and recognized text. Sort by `occurredAt`, kind raw value, then UUID.

- [ ] **Step 5: Run focused tests and commit**

Run `Scripts/test.sh --filter RecallTests`.

Commit: `feat: project stored evidence for personal recall`.

### Task 2: Implement inspectable lexical and semantic retrieval

**Files:**
- Modify: `Sources/ADHDCore/Recall.swift`
- Modify: `Tests/ADHDCoreTests/RecallTests.swift`

- [ ] **Step 1: Write failing exact-ranking tests**

Test Unicode letter/number tokenization, case/diacritic folding, exact phrase rank, token coverage, five-result default limit, and deterministic date/kind/UUID ties. Use:

```swift
let result = try await loop.retrieve(RecallQuery(text: "exact restart action"))
#expect(result.hits.first?.evidenceID == expectedReturnPacketID)
#expect(result.hits.first?.contributions.contains { $0.kind == .exactPhrase })
```

- [ ] **Step 2: Write failing semantic/fallback tests**

Use a fixture `EmbeddingProvider` mapping “launch discussion” near “release conversation”. Verify semantic-only evidence appears, lexical evidence remains first when strong, provider failure still returns exact results, and an empty normalized query throws `RecallError.emptyQuery`.

- [ ] **Step 3: Implement retrieval contracts and scoring**

Define:

```swift
public protocol EmbeddingProvider: Sendable {
    var identifier: String { get async }
    func vectors(for texts: [String]) async throws -> [[Double]]
}

public protocol RecallIndexStore: Sendable {
    func load() async throws -> RecallIndexSnapshot?
    func save(_ snapshot: RecallIndexSnapshot) async throws
    func discard() async throws
}

public protocol RecallSearching: Sendable {
    func retrieve(_ query: RecallQuery) async throws -> RecallResult
}
```

`RecallIndexSnapshot` stores provider identifier, documents, and equal-count vectors. `RecallLoop.retrieve` rebuilds when provider/documents change, but provider failure runs lexical-only. Exact phrase contributes `1.0`; token coverage is intersection count divided by distinct query-token count; semantic similarity is cosine mapped to `0...1`. Combined score is `0.65 * lexical + 0.35 * semantic`; semantic-only hits require `>= 0.55`. Return at most the query limit, default five.

- [ ] **Step 4: Add inspectable result values**

`RecallHit` exposes evidence ID, title, exact stored excerpt, date, total score, and `[RecallContribution]` using `.exactPhrase`, `.tokenCoverage`, and `.semanticSimilarity`. No synthesized answer field exists.

- [ ] **Step 5: Run focused tests and commit**

Run `Scripts/test.sh --filter RecallTests`.

Commit: `feat: rank exact and semantic recall evidence`.

### Task 3: Encrypt the derived recall index independently

**Files:**
- Create: `Sources/VaultStore/EncryptedRecallIndexStore.swift`
- Create: `Tests/VaultStoreTests/EncryptedRecallIndexStoreTests.swift`

- [ ] **Step 1: Write failing encrypted-index tests**

Persist a snapshot containing a distinctive document phrase/vector, reopen it, and assert equality. Scan every index byte for the phrase. Verify a different root key cannot decode it and malformed data loads as `nil` after being discarded rather than affecting the authoritative vault.

- [ ] **Step 2: Implement derived-key persistence**

Derive a 256-bit key with HKDF-SHA256 using info `openloop.recall.index.key.v1`. Encrypt sorted-key JSON with AES-GCM and authenticated data `openloop.recall.index|schema=1|content=derived`. Write atomically with complete file protection to `openloop-recall.index`. Serialize access in an actor.

- [ ] **Step 3: Make corruption a rebuildable cache miss**

Authentication/decode failure removes only `openloop-recall.index` and returns `nil`. Wrong root key returns `nil`; it never modifies `openloop.vault`. `discard()` is idempotent.

- [ ] **Step 4: Run focused tests and commit**

Run `Scripts/test.sh --filter EncryptedRecallIndexStoreTests`.

Commit: `feat: encrypt rebuildable personal recall index`.

### Task 4: Add the production local embedding adapter and model state

**Files:**
- Create: `Sources/OpenLoopApp/NaturalLanguageEmbeddingProvider.swift`
- Modify: `Sources/OpenLoopApp/AppModel.swift`
- Modify: `Sources/OpenLoopApp/OpenLoopApp.swift`
- Modify: `Package.swift`
- Create: `Tests/OpenLoopAppTests/AppModelRecallTests.swift`

- [ ] **Step 1: Write failing AppModel recall tests**

Inject a `RecallSearching` seam. Verify normalized queries publish loading then hits, empty text clears results without calling search, a second query supersedes the first result, and failures show “Exact search is still available after reopening Recall.” without affecting capture/focus state.

- [ ] **Step 2: Implement Apple Natural Language vectors**

Create an actor conforming to `EmbeddingProvider`. Use `NLEmbedding.sentenceEmbedding(for: .english)` and `vector(for:)`. Identifier is `apple-natural-language-sentence-en-r<revision>`. Throw `NaturalLanguageEmbeddingError.unavailable` or `.missingVector`; the recall loop then preserves lexical results.

- [ ] **Step 3: Add recall model state**

Publish `recallQuery`, `recallHits`, `isRecalling`, and `recallError`. `searchRecall(_:)` cancels the previous task token, trims input, runs the injected loop, ignores stale completions, and never changes `commandError` or capture state.

- [ ] **Step 4: Wire production dependencies**

Load the root key once, initialize `EncryptedThoughtRepository(directory:keyData:)`, `EncryptedRecallIndexStore(directory:rootKeyData:)`, `NaturalLanguageEmbeddingProvider`, `RecallDocumentSource`, and `RecallLoop`. Add `.linkedFramework("NaturalLanguage")`.

- [ ] **Step 5: Run focused tests and commit**

Run `Scripts/test.sh --filter AppModelRecallTests`.

Commit: `feat: connect local semantic recall`.

### Task 5: Ship the Recall surface, menu action, and global shortcut

**Files:**
- Modify: `Sources/OpenLoopApp/MainWindowController.swift`
- Modify: `Sources/OpenLoopApp/OpenLoopApp.swift`
- Modify: `Sources/OpenLoopApp/GlobalHotKey.swift`
- Modify: `Tests/OpenLoopAppTests/MainWindowControllerTests.swift`

- [ ] **Step 1: Write failing navigation tests**

Assert `mainWindow.show(tab: 3)` selects Recall and the app exposes distinct hot-key ID `3`, key `F`, modifiers Command-Shift without changing IDs 1 and 2.

- [ ] **Step 2: Add the calm editorial Recall tab**

Add the fourth `TabView` item labeled Recall. The view has one large native search field, `Search` button, `Command-Shift-F` hint, neutral empty/loading/error states, and flat evidence rows. Each row shows title, stored excerpt, relative date, evidence kind, total score, and compact labeled contribution bars. Use system typography, control background, 1px separators, maximum 12pt radius, no gradients, heavy shadows, scores framed as productivity, or generated-answer copy.

- [ ] **Step 3: Add menu and shortcut routing**

Register `Command-Shift-F` with hot-key ID 3. It opens tab 3 and focuses the Recall surface. Add `Recall` after `Later` in the menu. Registration failure reports through `recallError` and leaves the menu action available.

- [ ] **Step 4: Run focused UI/navigation tests and commit**

Run `Scripts/test.sh --filter 'MainWindowControllerTests|AppModelRecallTests'`.

Commit: `feat: add one-shortcut personal recall surface`.

### Task 6: Add recall evaluation, latency diagnostic, and documentation

**Files:**
- Modify: `Sources/ADHDCore/Recall.swift`
- Modify: `Sources/OpenLoopApp/OpenLoopApp.swift`
- Modify: `Tests/ADHDCoreTests/RecallTests.swift`
- Create: `Tests/Fixtures/recall-evaluation.json`
- Modify: `README.md`
- Modify: `docs/DECISIONS.md`
- Modify: `Resources/Info.plist`
- Modify: `.ai/plans/2026-08-17-personal-recall.md`

- [ ] **Step 1: Add deterministic evaluation values**

`RecallEvaluationCase` contains query and expected `[RecallEvidenceID]`. `RecallEvaluationReport` computes case count, top-five hit rate, and exact-search nearest-rank p95 milliseconds. Empty evaluation reports `nil` metrics rather than passing.

- [ ] **Step 2: Add a mixed fixture and diagnostic**

Create at least eight documents and five queries spanning capture, intention, return packet, correction, exact, and semantic retrieval. `--recall-evaluation <fixture.json>` prints stable sample count, top-five hit rate, and exact p95. Malformed fixtures exit nonzero. The output says `fixture`, not `personal corpus`.

- [ ] **Step 3: Document the privacy and quality boundary**

README documents Recall, `Command-Shift-F`, evidence-only results, local semantics, index rebuild, fixture command, and latency targets. Decision D-017 records encrypted derived retrieval, Apple Natural Language selection, inspectable hybrid rank, and the unresolved personal 95% gate. Set bundle version `0.5.0`.

- [ ] **Step 4: Run only focused Increment 5 tests**

Run:

```bash
Scripts/test.sh --filter 'RecallTests|EncryptedRecallIndexStoreTests|AppModelRecallTests|MainWindowControllerTests'
```

Do not run the exhaustive Increment gate unless the user asks.

- [ ] **Step 5: Commit the Increment 5 handoff**

Commit: `feat: complete evidence-first personal recall`.

Expected focused evidence: every stored evidence type projects into recall; exact and semantic ranking is stable and inspectable; semantic failure preserves lexical results; the separate index survives restart without plaintext; Recall is reachable by tab, menu, and `Command-Shift-F`; fixture top-five and p95 metrics are reproducible without being presented as personal acceptance.
