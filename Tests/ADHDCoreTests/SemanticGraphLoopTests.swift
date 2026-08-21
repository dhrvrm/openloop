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

private struct SemanticFixtureEmbeddings: EmbeddingProvider {
    let values: [String: [Double]]
    var identifier: String { get async { "semantic-fixture-v1" } }

    func vectors(for texts: [String]) async throws -> [[Double]] {
        try texts.map { text in
            guard let vector = values[text] else { throw RecallError.embeddingUnavailable }
            return vector
        }
    }
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
    #expect(try await loop.ask("checkout performance").map(\.node) == [problem])
}

@Test func askCombinesStoredVectorsWithEvidenceAndGraphContext() async throws {
    let repository = SemanticLoopRepository()
    let query = "What did I notice about payment speed?"
    let checkout = try SemanticNode(
        kind: .problem,
        claim: "Checkout performance degraded after PostHog",
        confidence: 0.84,
        status: .active,
        evidence: [try SemanticEvidence(
            id: RecallEvidenceID(kind: .capture, id: UUID()),
            excerpt: "Checkout became slow after analytics changed",
            occurredAt: Date(timeIntervalSince1970: 60)
        )],
        createdAt: Date(timeIntervalSince1970: 60)
    )
    let unrelated = try SemanticNode(
        kind: .idea,
        claim: "Separate authentication module",
        confidence: 0.9,
        status: .active,
        evidence: [try SemanticEvidence(
            id: RecallEvidenceID(kind: .capture, id: UUID()),
            excerpt: "Split auth into its own module",
            occurredAt: Date(timeIntervalSince1970: 61)
        )],
        createdAt: Date(timeIntervalSince1970: 61)
    )
    let provider = SemanticFixtureEmbeddings(values: [
        query: [1, 0, 0],
    ])
    let loop = SemanticGraphLoop(repository: repository, embeddingProvider: provider)
    try await loop.append([
        .node(id: UUID(), occurredAt: checkout.createdAt, value: checkout),
        .node(id: UUID(), occurredAt: unrelated.createdAt, value: unrelated),
        .vector(
            id: UUID(),
            occurredAt: checkout.createdAt,
            nodeID: checkout.id,
            value: try SemanticVector(
                providerIdentifier: "semantic-fixture-v1",
                values: [0.98, 0.02, 0]
            )
        ),
        .vector(
            id: UUID(),
            occurredAt: unrelated.createdAt,
            nodeID: unrelated.id,
            value: try SemanticVector(
                providerIdentifier: "semantic-fixture-v1",
                values: [0, 1, 0]
            )
        ),
    ])

    let answers = try await loop.ask(query)

    #expect(answers.map(\.node) == [checkout])
    #expect(answers[0].node.evidence.count == 1)
    #expect(!answers[0].history.isEmpty)
}

@Test func askResolvesAnOldBeliefToItsCurrentSupersedingBelief() async throws {
    let repository = SemanticLoopRepository()
    let loop = SemanticGraphLoop(repository: repository)
    let evidenceID = RecallEvidenceID(kind: .capture, id: UUID())
    let old = try SemanticNode(
        kind: .decision,
        claim: "Use Redis for sessions",
        confidence: 1,
        status: .active,
        evidence: [try SemanticEvidence(
            id: evidenceID,
            excerpt: "We decided to use Redis for sessions",
            occurredAt: Date(timeIntervalSince1970: 70)
        )],
        createdAt: Date(timeIntervalSince1970: 70)
    )
    let current = try SemanticNode(
        kind: .decision,
        claim: "Use Postgres for sessions",
        confidence: 1,
        status: .active,
        evidence: [try SemanticEvidence(
            id: RecallEvidenceID(kind: .capture, id: UUID()),
            excerpt: "We changed the session store to Postgres",
            occurredAt: Date(timeIntervalSince1970: 80)
        )],
        createdAt: Date(timeIntervalSince1970: 80)
    )
    try await loop.append([
        .node(id: UUID(), occurredAt: old.createdAt, value: old),
        .node(id: UUID(), occurredAt: current.createdAt, value: current),
        .supersession(
            id: UUID(),
            occurredAt: Date(timeIntervalSince1970: 80),
            oldID: old.id,
            newID: current.id
        ),
    ])

    let answers = try await loop.ask("Redis sessions")

    #expect(answers.map(\.node) == [current])
    #expect(answers[0].related.contains(where: { $0.id == old.id }))
    #expect(answers[0].history.contains(where: { event in
        if case .supersession = event { return true }
        return false
    }))
}

@Test func recurringDerivedMeaningsConsolidateWithoutDeletingEpisodeEvidence() async throws {
    let repository = SemanticLoopRepository()
    let loop = SemanticGraphLoop(repository: repository)
    var problems: [SemanticNode] = []
    var events: [SemanticGraphEvent] = []
    for index in 0..<3 {
        let evidence = try SemanticEvidence(
            id: RecallEvidenceID(kind: .capture, id: UUID()),
            excerpt: "Checkout was slow in episode \(index)",
            occurredAt: Date(timeIntervalSince1970: Double(90 + index))
        )
        let node = try SemanticNode(
            kind: .problem,
            claim: index == 2 ? "Checkout performance remains slow" : "Checkout is slow",
            confidence: 0.8 + (Double(index) * 0.05),
            status: .active,
            evidence: [evidence],
            createdAt: evidence.occurredAt
        )
        problems.append(node)
        events.append(.node(id: UUID(), occurredAt: node.createdAt, value: node))
    }
    for pair in zip(problems, problems.dropFirst()) {
        events.append(.relation(
            id: UUID(),
            occurredAt: pair.1.createdAt,
            value: try SemanticRelation(
                sourceID: pair.0.id,
                targetID: pair.1.id,
                kind: .relatesTo,
                confidence: 0.93,
                createdAt: pair.1.createdAt
            )
        ))
    }
    try await loop.append(events)

    let consolidated = try await loop.consolidateRecurringClaims()
    let graph = try await loop.graph()

    #expect(consolidated.count == 1)
    #expect(consolidated[0].claim == "Checkout performance remains slow")
    #expect(consolidated[0].evidence.count == 3)
    #expect(problems.allSatisfy { graph.nodes[$0.id]?.status == .superseded })
    #expect(problems.allSatisfy { graph.nodes[$0.id] != nil })
    #expect(try await loop.consolidateRecurringClaims().isEmpty)
    #expect(try SemanticGraph(events: graph.events) == graph)
}

@Test func semanticExtractionPreservesUncertaintyAndGroundsEveryMeaning() async throws {
    let repository = SemanticLoopRepository()
    let loop = SemanticGraphLoop(repository: repository)
    let capture = try RawCapture(
        createdAt: Date(timeIntervalSince1970: 45),
        text: "Maybe we should migrate to Postgres. Can we reduce release time?"
    )

    let nodes = try await loop.recordSemantics(capture: capture)
    let graph = try await loop.graph()

    #expect(nodes.map(\.kind).contains(.observation))
    #expect(nodes.map(\.kind).contains(.possibility))
    #expect(nodes.map(\.kind).contains(.question))
    #expect(nodes.map(\.kind).contains(.decision) == false)
    #expect(nodes.map(\.kind).contains(.action) == false)
    #expect(nodes.map(\.kind).contains(.intention) == false)
    #expect(nodes.filter { $0.kind != .observation }.allSatisfy {
        $0.evidence.map(\.id) == [RecallEvidenceID(kind: .capture, id: capture.id)]
    })
    #expect(graph.relations.values.count == nodes.count - 1)

    let replayed = try await loop.recordSemantics(capture: capture)
    #expect(Set(replayed.map(\.id)) == Set(nodes.map(\.id)))
    #expect(try await loop.graph() == graph)
}

@Test func semanticExtractionUnderstandsExplicitEnglishHindiAndHinglishSignals() async throws {
    let extractor = SemanticCandidateExtractor()

    #expect(extractor.extract(from: "Checkout is slow after PostHog.").map(\.kind) == [.problem])
    #expect(extractor.extract(from: "We decided to keep Redis.").map(\.kind) == [.decision])
    #expect(extractor.extract(from: "I will send the release note.").map(\.kind) == [.intention])
    #expect(extractor.extract(from: "क्या हम release time कम कर सकते हैं?").map(\.kind) == [.question])
    #expect(extractor.extract(from: "शायद auth module अलग करना चाहिए।").map(\.kind) == [.possibility])
    #expect(extractor.extract(from: "Build galat output de raha hai.").map(\.kind) == [.problem])
}

@Test func semanticGraphLoopStoresVectorsAndGroundedSimilarityRelations() async throws {
    let repository = SemanticLoopRepository()
    let firstText = "Checkout performance after PostHog"
    let secondText = "Investigate checkout performance"
    let loop = SemanticGraphLoop(
        repository: repository,
        embeddingProvider: SemanticFixtureEmbeddings(values: [
            firstText: [1, 0, 0],
            secondText: [0.9, 0.1, 0],
        ])
    )
    let first = try await loop.recordObservation(capture: RawCapture(
        createdAt: Date(timeIntervalSince1970: 50),
        text: firstText
    ))
    let second = try await loop.recordObservation(capture: RawCapture(
        createdAt: Date(timeIntervalSince1970: 51),
        text: secondText
    ))

    _ = try await loop.enrichVector(nodeID: first.id, text: first.claim)
    _ = try await loop.enrichVector(nodeID: second.id, text: second.claim)
    let graph = try await loop.graph()

    #expect(graph.vectors.count == 2)
    #expect(graph.relations.values.contains {
        $0.kind == .relatesTo
            && Set([$0.sourceID, $0.targetID]) == Set([first.id, second.id])
    })
}

@Test func meetingSemanticsAreExtractiveEvidenceLinkedAndIdempotent() async throws {
    let repository = SemanticLoopRepository()
    let loop = SemanticGraphLoop(repository: repository)
    let segment = try TranscriptSegment(
        start: 5,
        end: 12,
        text: "Can we reduce release time? We decided to automate checks. Dhruv will publish notes."
    )
    let transcript = try MeetingTranscript(
        sourceName: "release.m4a",
        createdAt: Date(timeIntervalSince1970: 100),
        duration: 12,
        modelIdentifier: "local",
        segments: [segment]
    )

    let nodes = try await loop.recordMeetingSemantics(transcript: transcript)
    let graph = try await loop.graph()

    #expect(nodes.map(\.kind).contains(.context))
    #expect(nodes.map(\.kind).contains(.question))
    #expect(nodes.map(\.kind).contains(.decision))
    #expect(nodes.map(\.kind).contains(.intention))
    #expect(nodes.map(\.kind).contains(.action) == false)
    #expect(nodes.filter { $0.kind != .context }.allSatisfy { node in
        node.evidence.allSatisfy { evidence in
            evidence.id.kind == .meetingTranscript
                && segment.text.contains(evidence.excerpt)
        }
    })
    #expect(graph.relations.values.count == nodes.count - 1)

    #expect(try await loop.recordMeetingSemantics(transcript: transcript).isEmpty)
    #expect(try await loop.graph() == graph)
}
