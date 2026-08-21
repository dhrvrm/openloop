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
