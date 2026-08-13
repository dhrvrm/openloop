# Proposed Connection Interfaces

Status: provisional implementation proposal. These are not formal
`SUBSYSTEM.md` contracts.

## Boundary rule

Each component owns one externally observable behavior. Components depend on a
small package of versioned `Codable` and `Sendable` values, never on another
component's concrete implementation.

Connections begin as in-process async commands and streams. Durable information
passes through an append-only event envelope so processing can be replayed after
a crash or model change.

## ADHD loop relations

| Producer | Meaning provided | Consumer |
| --- | --- | --- |
| Capture adapter | unstructured externalized thought | capture journal |
| Capture journal | durable raw capture | clarification, search |
| Clarification | proposed disposition and next action | user review, intention ledger |
| Intention ledger | accepted open, active, interrupted, or closed loop | Now, resurfacing, recall |
| Focus orientation | active intention and elapsed context | interruption recovery, Now |
| Context adapter | optional local environmental cue | interruption recovery, resurfacing |
| Interruption recovery | restart packet | Return, intention ledger |
| Resurfacing | contextually relevant suggestion | menu bar, Return |
| Memory compiler | evidence-backed temporal memory | memory ledger |
| Memory ledger | current and historical personal knowledge | retrieval |
| Retrieval | ranked evidence, intentions, and memories | Recall |
| Runtime governor | resource grant or degradation state | model-backed adapters |
| Retention policy | keep, expire, or delete decision | vault repository |

Voice is simply another capture adapter:

```text
microphone -> speech provider -> raw text capture -> existing ADHD loop
```

The rest of the product neither knows nor cares whether a thought was typed,
spoken, imported, or created from a future local context adapter.

## Shared envelope

```swift
public struct EventEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public let id: UUID
    public let schemaVersion: UInt16
    public let sequence: UInt64
    public let occurredAt: Date
    public let producer: ComponentID
    public let correlationID: UUID
    public let payload: Payload
}
```

Rules:

- event ID provides idempotency;
- sequence is monotonic within one local journal;
- occurrence time describes the user's event, not later processing;
- correlation ID joins derived information to its originating capture;
- consumers checkpoint the last accepted sequence;
- replay produces no duplicate durable state;
- additive schema changes retain compatibility; breaking changes increment the
  schema version.

## Core values

```swift
public struct RawCapture: Codable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let source: CaptureSource
    public let content: CaptureContent
}

public struct ClarificationProposal: Codable, Sendable {
    public let captureID: UUID
    public let disposition: Disposition
    public let desiredOutcome: String?
    public let nextAction: String?
    public let confidence: Double
}

public struct Intention: Codable, Sendable {
    public let id: UUID
    public let sourceCaptureID: UUID
    public let desiredOutcome: String
    public let nextAction: String
    public let state: IntentionState
    public let createdAt: Date
}

public struct ReturnPacket: Codable, Sendable {
    public let intentionID: UUID
    public let capturedAt: Date
    public let justCompleted: String?
    public let nextAction: String
    public let blocker: String?
    public let references: [LocalReference]
}

public struct MemoryRecord: Codable, Sendable {
    public let id: UUID
    public let version: UInt32
    public let kind: MemoryKind
    public let statement: String
    public let confidence: Double
    public let evidence: [EvidenceReference]
    public let supersedes: [UUID]
}
```

## Command interfaces

```swift
public protocol CaptureProvider: Sendable {
    func captures() -> AsyncThrowingStream<EventEnvelope<RawCapture>, Error>
}

public protocol ClarificationProvider: Sendable {
    func propose(for capture: RawCapture) async throws -> ClarificationProposal
}

public protocol IntentionRepository: Sendable {
    func accept(_ proposal: ClarificationProposal) async throws -> Intention?
    func transition(_ id: UUID, to state: IntentionState) async throws
    func openIntentions() async throws -> [Intention]
}

public protocol InterruptionRecorder: Sendable {
    func snapshot(_ request: SnapshotRequest) async throws -> ReturnPacket
}

public protocol ResurfacingProvider: Sendable {
    func suggestions(for context: ResurfacingContext) async throws -> [Suggestion]
}

public protocol VaultRepository: Sendable {
    func append<P>(_ envelope: EventEnvelope<P>) async throws where P: Codable & Sendable
    func retrieve(_ query: RecallQuery) async throws -> RecallResult
}
```

## Failure and performance behavior

- Capture persists before clarification begins.
- A model failure leaves the raw thought safely available.
- Empty or uncertain clarification remains unforced.
- Quick Capture does not wait for encryption compaction, embedding, or a model.
- When local storage is unavailable, the interface reports that capture failed;
  it never closes as if the thought was saved.
- High thermal pressure defers speech refinement and memory compilation.
- Private Mode disables ambient adapters without disabling manual capture.
- Every provider can be replaced by a fixture implementation in tests.

## Extensibility test

A component boundary passes when its producer can be replaced by recorded
fixtures, its consumer remains unchanged, and an alternative provider can be
selected without migrating the stored meaning.
