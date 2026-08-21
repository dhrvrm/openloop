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

    #expect(model.semanticNodes.map(\.claim) == ["Checkout is slower after PostHog"])
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
