import Foundation
import Testing
@testable import ADHDCore

private func semanticEvidence(_ text: String, id: UUID = UUID()) throws -> SemanticEvidence {
    try SemanticEvidence(
        id: RecallEvidenceID(kind: .capture, id: id),
        excerpt: text,
        occurredAt: Date(timeIntervalSince1970: 10)
    )
}

@Test func semanticGraphPreservesSpeculationInsteadOfInventingDecision() throws {
    let evidence = try semanticEvidence("Maybe we should migrate to Postgres")
    let node = try SemanticNode(
        kind: .possibility,
        claim: "Migrate to Postgres",
        confidence: 0.82,
        status: .speculative,
        evidence: [evidence]
    )
    var graph = try SemanticGraph()
    try graph.apply(.node(id: UUID(), occurredAt: .now, value: node))

    #expect(graph.nodes[node.id]?.kind == .possibility)
    #expect(graph.nodes[node.id]?.status == .speculative)
    #expect(graph.nodes[node.id]?.confidence == 0.82)
    #expect(graph.nodes[node.id]?.evidence == [evidence])
}

@Test func semanticGraphPersistsValidatedVectorsThroughEventReplay() throws {
    let node = try SemanticNode(
        kind: .concept,
        claim: "Local semantic memory",
        confidence: 0.9,
        status: .active,
        evidence: [try semanticEvidence("Local semantic memory")]
    )
    let vector = try SemanticVector(
        providerIdentifier: "fixture-v1",
        values: [0.25, -0.5, 0.75],
        createdAt: Date(timeIntervalSince1970: 20)
    )
    let events: [SemanticGraphEvent] = [
        .node(id: UUID(), occurredAt: .now, value: node),
        .vector(id: UUID(), occurredAt: .now, nodeID: node.id, value: vector),
    ]

    let graph = try SemanticGraph(events: events)

    #expect(graph.vectors[node.id] == vector)
    #expect(graph.history(for: node.id).count == 2)
}

@Test func semanticGraphRejectsInvalidOrUngroundedVectors() throws {
    #expect(throws: SemanticGraphError.invalidVectorDimensions(2)) {
        try SemanticVector(providerIdentifier: "fixture", values: [0, 1])
    }
    #expect(throws: SemanticGraphError.invalidVectorValue) {
        try SemanticVector(providerIdentifier: "fixture", values: [0, .nan, 1])
    }

    let vector = try SemanticVector(providerIdentifier: "fixture", values: [0, 1, 2])
    #expect(throws: SemanticGraphError.missingNode(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)) {
        var graph = try SemanticGraph()
        let missingID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        try graph.apply(.vector(id: UUID(), occurredAt: .now, nodeID: missingID, value: vector))
    }
}

@Test func supersessionKeepsOldBeliefAndQueryableHistory() throws {
    let old = try SemanticNode(
        kind: .decision,
        claim: "Use Redis for sessions",
        confidence: 1,
        status: .active,
        evidence: [try semanticEvidence("Decision: use Redis")]
    )
    let new = try SemanticNode(
        kind: .decision,
        claim: "Use Postgres for sessions",
        confidence: 1,
        status: .active,
        evidence: [try semanticEvidence("Decision changed to Postgres")]
    )
    var graph = try SemanticGraph()
    try graph.apply(.node(id: UUID(), occurredAt: .now, value: old))
    try graph.apply(.node(id: UUID(), occurredAt: .now, value: new))
    try graph.apply(.supersession(
        id: UUID(),
        occurredAt: .now,
        oldID: old.id,
        newID: new.id
    ))

    #expect(graph.nodes[old.id]?.status == .superseded)
    #expect(graph.nodes[old.id]?.supersededBy == new.id)
    #expect(graph.nodes[new.id]?.status == .active)
    #expect(graph.history(for: old.id).count == 2)

    let replayed = try SemanticGraph(events: graph.events)
    #expect(replayed == graph)
}

@Test func projectionsSurfaceEmergingAndUnresolvedWithoutCreatingTasks() throws {
    let project = try SemanticNode(
        kind: .project,
        claim: "Storefront",
        confidence: 1,
        status: .active,
        evidence: [try semanticEvidence("Storefront")]
    )
    let problem = try SemanticNode(
        kind: .problem,
        claim: "Checkout performance degraded after PostHog",
        confidence: 0.71,
        status: .active,
        evidence: [try semanticEvidence("Checkout is slow after PostHog")]
    )
    let action = try SemanticNode(
        kind: .action,
        claim: "Investigate checkout performance",
        confidence: 0.55,
        status: .speculative,
        evidence: [try semanticEvidence("We could investigate")]
    )
    var graph = try SemanticGraph()
    for node in [project, problem, action] {
        try graph.apply(.node(id: UUID(), occurredAt: .now, value: node))
    }
    try graph.apply(.relation(
        id: UUID(),
        occurredAt: .now,
        value: try SemanticRelation(
            sourceID: problem.id,
            targetID: project.id,
            kind: .partOf,
            confidence: 0.9
        )
    ))
    try graph.apply(.relation(
        id: UUID(),
        occurredAt: .now,
        value: try SemanticRelation(
            sourceID: problem.id,
            targetID: action.id,
            kind: .suggestsAction,
            confidence: 0.55
        )
    ))

    let projection = SemanticGraphProjection()
    #expect(projection.unresolved(in: graph) == [problem])
    #expect(projection.emerging(in: graph).first?.node == problem)
    #expect(graph.nodes[action.id]?.status == .speculative)
}

@Test func askContextReturnsEvidenceGroundedActiveNodes() throws {
    let checkout = try SemanticNode(
        kind: .problem,
        claim: "Checkout performance degraded after PostHog",
        confidence: 0.8,
        status: .active,
        evidence: [try semanticEvidence("checkout became slow")]
    )
    let auth = try SemanticNode(
        kind: .idea,
        claim: "Separate authentication module",
        confidence: 0.7,
        status: .active,
        evidence: [try semanticEvidence("split auth")]
    )
    var graph = try SemanticGraph()
    try graph.apply(.node(id: UUID(), occurredAt: .now, value: checkout))
    try graph.apply(.node(id: UUID(), occurredAt: .now, value: auth))

    let answers = SemanticGraphProjection().ask("What was wrong with checkout?", in: graph)

    #expect(answers == [checkout])
    #expect(!answers[0].evidence.isEmpty)
}

@Test func semanticGraphRejectsDuplicateEventIdentifiers() throws {
    let eventID = UUID()
    let first = try SemanticNode(
        kind: .observation,
        claim: "Checkout slowed down",
        confidence: 0.8,
        status: .active,
        evidence: [try semanticEvidence("Checkout is slow")]
    )
    let second = try SemanticNode(
        kind: .observation,
        claim: "Authentication became coupled",
        confidence: 0.7,
        status: .active,
        evidence: [try semanticEvidence("Auth is coupled")]
    )
    var graph = try SemanticGraph()
    try graph.apply(.node(id: eventID, occurredAt: .now, value: first))

    #expect(throws: SemanticGraphError.duplicateEvent(eventID)) {
        try graph.apply(.node(id: eventID, occurredAt: .now, value: second))
    }
    #expect(graph.events.count == 1)
    #expect(graph.nodes[second.id] == nil)
}
