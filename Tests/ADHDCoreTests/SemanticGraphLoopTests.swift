import Foundation
import Testing
@testable import ADHDCore

private actor SemanticLoopRepository: ThoughtRepository {
    private var events: [SemanticGraphEvent] = []

    func save(capture: RawCapture) async throws {}
    func save(proposal: ClarificationProposal) async throws {}
    func save(intention: Intention) async throws {}
    func proposal(captureID: UUID) async throws -> ClarificationProposal? { nil }
    func captures(disposition: Disposition) async throws -> [RawCapture] { [] }
    func intention(id: UUID) async throws -> Intention? { nil }
    func openIntentions() async throws -> [Intention] { [] }
    func append(semanticGraphEvents newEvents: [SemanticGraphEvent]) async throws {
        _ = try SemanticGraph(events: events + newEvents)
        events.append(contentsOf: newEvents)
    }
    func semanticGraphEvents() async throws -> [SemanticGraphEvent] { events }
}

@Test func semanticGraphLoopRecordsGroundedObservationWithoutInventingAnAction() async throws {
    let repository = SemanticLoopRepository()
    let loop = SemanticGraphLoop(repository: repository)
    let capture = try RawCapture(
        createdAt: Date(timeIntervalSince1970: 30),
        text: "Maybe checkout is slower after PostHog"
    )

    let node = try await loop.recordObservation(capture: capture)
    let graph = try await loop.graph()

    #expect(node.kind == .observation)
    #expect(node.claim == capture.text)
    #expect(node.confidence == 1)
    #expect(node.status == .active)
    #expect(node.evidence.map(\.id) == [RecallEvidenceID(kind: .capture, id: capture.id)])
    #expect(graph.nodes[node.id] == node)
    #expect(graph.nodes.values.contains(where: { $0.kind == .action }) == false)
}

@Test func semanticGraphLoopProjectsDurableEventsForEmergingAndAsk() async throws {
    let repository = SemanticLoopRepository()
    let loop = SemanticGraphLoop(repository: repository)
    let evidence = try SemanticEvidence(
        id: RecallEvidenceID(kind: .capture, id: UUID()),
        excerpt: "Checkout performance is unresolved",
        occurredAt: Date(timeIntervalSince1970: 40)
    )
    let problem = try SemanticNode(
        kind: .problem,
        claim: "Checkout performance is unresolved",
        confidence: 0.9,
        status: .active,
        evidence: [evidence]
    )
    try await loop.append([
        .node(id: UUID(), occurredAt: .now, value: problem),
    ])

    #expect(try await loop.unresolved() == [problem])
    #expect(try await loop.ask("checkout performance") == [problem])
}
