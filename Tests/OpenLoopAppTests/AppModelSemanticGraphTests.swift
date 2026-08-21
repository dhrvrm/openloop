import ADHDCore
import Foundation
import Testing
@testable import OpenLoopApp

private actor SemanticAppRepository: ThoughtRepository {
    private var captures: [UUID: RawCapture] = [:]
    private var events: [SemanticGraphEvent] = []

    func save(capture: RawCapture) async throws { captures[capture.id] = capture }
    func save(proposal: ClarificationProposal) async throws {}
    func save(intention: Intention) async throws {}
    func proposal(captureID: UUID) async throws -> ClarificationProposal? { nil }
    func captures(disposition: Disposition) async throws -> [RawCapture] { [] }
    func intention(id: UUID) async throws -> Intention? { nil }
    func openIntentions() async throws -> [Intention] { [] }
    func allCaptures() async throws -> [RawCapture] { Array(captures.values) }
    func append(semanticGraphEvents newEvents: [SemanticGraphEvent]) async throws {
        _ = try SemanticGraph(events: events + newEvents)
        events.append(contentsOf: newEvents)
    }
    func semanticGraphEvents() async throws -> [SemanticGraphEvent] { events }
}

private struct SemanticUnusedClarifier: ClarificationProvider {
    func propose(for capture: RawCapture) async throws -> ClarificationProposal {
        try ClarificationProposal(
            captureID: capture.id,
            disposition: .memory,
            desiredOutcome: nil,
            nextAction: nil,
            confidence: 1
        )
    }
}

@MainActor
@Test func appModelPublishesGroundedContextAfterCaptureAndAnswersLocally() async throws {
    let repository = SemanticAppRepository()
    let semanticLoop = SemanticGraphLoop(repository: repository)
    let model = AppModel(
        loop: ThoughtLoop(repository: repository, clarifier: SemanticUnusedClarifier()),
        readModels: ThoughtReadModels(repository: repository),
        semanticGraph: semanticLoop
    )

    #expect(await model.submitCapture("Checkout is slower after PostHog"))
    await model.refreshSemanticGraph()
    await model.askSemanticContext("checkout")

    #expect(model.semanticNodes.map(\.claim) == [
        "Checkout is slower after PostHog", "Checkout is slower after PostHog",
    ])
    #expect(Set(model.semanticNodes.map(\.kind)) == [.observation, .problem])
    #expect(model.semanticAnswers.map(\.claim) == ["Checkout is slower after PostHog"])
    #expect(model.semanticError == nil)
}

@MainActor
@Test func emptySemanticQuestionClearsAnswersWithoutInventingContent() async {
    let repository = SemanticAppRepository()
    let model = AppModel(
        loop: ThoughtLoop(repository: repository, clarifier: SemanticUnusedClarifier()),
        readModels: ThoughtReadModels(repository: repository),
        semanticGraph: SemanticGraphLoop(repository: repository)
    )

    await model.askSemanticContext("   ")

    #expect(model.semanticAnswers.isEmpty)
    #expect(model.semanticError == nil)
}

@MainActor
@Test func appModelPublishesStoredRelationsAndVectorsWithoutSynthesizingThem() async throws {
    let repository = SemanticAppRepository()
    let first = try SemanticNode(
        kind: .project,
        claim: "OpenLoop",
        confidence: 1,
        status: .active,
        evidence: [try SemanticEvidence(
            id: RecallEvidenceID(kind: .capture, id: UUID()),
            excerpt: "OpenLoop",
            occurredAt: .now
        )]
    )
    let second = try SemanticNode(
        kind: .problem,
        claim: "Release reliability",
        confidence: 0.8,
        status: .active,
        evidence: [try SemanticEvidence(
            id: RecallEvidenceID(kind: .capture, id: UUID()),
            excerpt: "Release reliability",
            occurredAt: .now
        )]
    )
    let relation = try SemanticRelation(
        sourceID: second.id,
        targetID: first.id,
        kind: .partOf,
        confidence: 0.9
    )
    let vector = try SemanticVector(
        providerIdentifier: "fixture-v1",
        values: [0.1, 0.2, 0.3]
    )
    try await repository.append(semanticGraphEvents: [
        .node(id: UUID(), occurredAt: .now, value: first),
        .node(id: UUID(), occurredAt: .now, value: second),
        .relation(id: UUID(), occurredAt: .now, value: relation),
        .vector(id: UUID(), occurredAt: .now, nodeID: second.id, value: vector),
    ])
    let model = AppModel(
        loop: ThoughtLoop(repository: repository, clarifier: SemanticUnusedClarifier()),
        readModels: ThoughtReadModels(repository: repository),
        semanticGraph: SemanticGraphLoop(repository: repository)
    )

    await model.refreshSemanticGraph()

    #expect(model.semanticRelations == [relation])
    #expect(model.semanticVectors == [second.id: vector])
}
