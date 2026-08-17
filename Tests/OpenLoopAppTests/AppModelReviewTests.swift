import ADHDCore
import Foundation
import Testing
@testable import OpenLoopApp

private actor ReviewRepository: ThoughtRepository {
    var captures: [UUID: RawCapture] = [:]
    var proposals: [UUID: ClarificationProposal] = [:]
    var intentions: [UUID: Intention] = [:]
    var corrections: [UUID: ClarificationCorrection] = [:]

    func save(capture: RawCapture) async throws { captures[capture.id] = capture }
    func capture(id: UUID) async throws -> RawCapture? { captures[id] }
    func save(proposal: ClarificationProposal) async throws { proposals[proposal.captureID] = proposal }
    func save(intention: Intention) async throws { intentions[intention.id] = intention }
    func apply(
        clarificationCorrection: ClarificationCorrection,
        intention: Intention?
    ) async throws {
        proposals[clarificationCorrection.captureID] = clarificationCorrection.proposal
        corrections[clarificationCorrection.id] = clarificationCorrection
        if let intention { intentions[intention.id] = intention }
    }
    func proposal(captureID: UUID) async throws -> ClarificationProposal? { proposals[captureID] }
    func captures(disposition: Disposition) async throws -> [RawCapture] {
        captures.values.filter { proposals[$0.id]?.disposition == disposition }
    }
    func unclarifiedCaptures() async throws -> [RawCapture] {
        captures.values.filter { proposals[$0.id] == nil }
    }
    func intention(id: UUID) async throws -> Intention? { intentions[id] }
    func openIntentions() async throws -> [Intention] {
        intentions.values.filter { $0.state != .closed && $0.state != .released }
    }
    func allCaptures() async throws -> [RawCapture] { Array(captures.values) }
    func allIntentions() async throws -> [Intention] { Array(intentions.values) }
}

private struct ReviewUnusedClarifier: ClarificationProvider {
    func propose(for capture: RawCapture) async throws -> ClarificationProposal {
        try ClarificationProposal(
            captureID: capture.id,
            disposition: .unclear,
            desiredOutcome: nil,
            nextAction: nil,
            confidence: 1
        )
    }
}

@Suite("AppModelReview")
@MainActor
struct AppModelReviewTests {
    @Test func correctionCreatesOneOpenLoopAndRefreshesReview() async throws {
        let repository = ReviewRepository()
        let capture = try RawCapture(createdAt: .now, text: "Reply to Riya")
        try await repository.save(capture: capture)
        let model = AppModel(
            loop: ThoughtLoop(repository: repository, clarifier: ReviewUnusedClarifier()),
            readModels: ThoughtReadModels(repository: repository)
        )
        _ = await model.refresh()

        let saved = await model.applyClarificationReview(
            captureID: capture.id,
            disposition: .action,
            desiredOutcome: "Riya has the answer",
            nextAction: "Open Riya's latest message"
        )

        #expect(saved)
        #expect(model.reviewItems.first?.disposition == .action)
        #expect(model.reviewItems.first?.intentionState == .open)
        #expect(model.openLoops.map(\.intentionID) == [capture.id])
        #expect(model.reviewError == nil)
    }

    @Test func invalidActionLeavesReviewVisibleWithCalmGuidance() async throws {
        let repository = ReviewRepository()
        let capture = try RawCapture(createdAt: .now, text: "Reply to Riya")
        try await repository.save(capture: capture)
        let model = AppModel(
            loop: ThoughtLoop(repository: repository, clarifier: ReviewUnusedClarifier()),
            readModels: ThoughtReadModels(repository: repository)
        )
        _ = await model.refresh()

        let saved = await model.applyClarificationReview(
            captureID: capture.id,
            disposition: .action,
            desiredOutcome: "Riya has the answer",
            nextAction: "   "
        )

        #expect(saved == false)
        #expect(model.reviewItems.map(\.id) == [capture.id])
        #expect(model.reviewError == "Add an outcome and one next action.")
    }
}
