import ADHDCore
import Foundation
import Testing
@testable import OpenLoopApp

private actor RecallSearchProbe: RecallSearching {
    enum Failure: Error { case unavailable }
    var calls: [String] = []
    var fail = false
    let hit: RecallHit

    init(hit: RecallHit) { self.hit = hit }

    func retrieve(_ query: RecallQuery) async throws -> RecallResult {
        calls.append(query.text)
        if fail { throw Failure.unavailable }
        return RecallResult(query: query.text, hits: [hit])
    }

    func setFailure(_ value: Bool) { fail = value }
}

@MainActor
@Test func appModelPublishesRecallResultsAndEmptyQueryClearsWithoutSearching() async throws {
    let hit = recallTestHit()
    let probe = RecallSearchProbe(hit: hit)
    let model = recallTestModel(search: probe)

    await model.searchRecall("  rollout notes  ")

    #expect(model.recallQuery == "rollout notes")
    #expect(model.recallHits == [hit])
    #expect(model.recallError == nil)
    #expect(await probe.calls == ["rollout notes"])

    await model.searchRecall("   ")
    #expect(model.recallHits.isEmpty)
    #expect(await probe.calls == ["rollout notes"])
}

@MainActor
@Test func appModelContainsRecallFailureWithoutChangingOtherState() async {
    let probe = RecallSearchProbe(hit: recallTestHit())
    let model = recallTestModel(search: probe)
    await probe.setFailure(true)

    await model.searchRecall("Mira")

    #expect(model.recallHits.isEmpty)
    #expect(model.recallError == "Exact search is still available after reopening Recall.")
    #expect(model.captureError == nil)
    #expect(model.commandError == nil)
}

private func recallTestHit() -> RecallHit {
    RecallHit(
        evidenceID: RecallEvidenceID(kind: .capture, id: UUID()),
        title: "Capture",
        excerpt: "Open the rollout notes",
        occurredAt: Date(timeIntervalSince1970: 1),
        score: 1,
        contributions: [RecallContribution(kind: .exactPhrase, value: 1)]
    )
}

@MainActor
private func recallTestModel(search: any RecallSearching) -> AppModel {
    let repository = RecallAppRepository()
    return AppModel(
        loop: ThoughtLoop(repository: repository, clarifier: RecallUnusedClarifier()),
        readModels: ThoughtReadModels(repository: repository),
        recallSearch: search
    )
}

private actor RecallAppRepository: ThoughtRepository {
    func save(capture: RawCapture) async throws {}
    func save(proposal: ClarificationProposal) async throws {}
    func save(intention: Intention) async throws {}
    func captures(disposition: Disposition) async throws -> [RawCapture] { [] }
    func intention(id: UUID) async throws -> Intention? { nil }
    func openIntentions() async throws -> [Intention] { [] }
    func proposal(captureID: UUID) async throws -> ClarificationProposal? { nil }
}

private struct RecallUnusedClarifier: ClarificationProvider {
    func propose(for capture: RawCapture) async throws -> ClarificationProposal {
        try ClarificationProposal(
            captureID: capture.id, disposition: .unclear,
            desiredOutcome: nil, nextAction: nil, confidence: 1
        )
    }
}
