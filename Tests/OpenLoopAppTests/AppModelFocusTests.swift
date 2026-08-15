import ADHDCore
import Foundation
import Testing
@testable import OpenLoopApp

private actor RefreshFailingRepository: ThoughtRepository {
    struct ReadFailure: Error {}

    var intentionValue: Intention
    var sessionValue: FocusSession?
    var failReads = false

    init(intention: Intention) { intentionValue = intention }

    func save(capture: RawCapture) async throws {}
    func save(proposal: ClarificationProposal) async throws {}
    func save(intention: Intention) async throws { intentionValue = intention }
    func save(focusSession: FocusSession) async throws { sessionValue = focusSession }
    func save(intention: Intention, focusSession: FocusSession) async throws {
        intentionValue = intention
        sessionValue = focusSession
        failReads = true
    }
    func proposal(captureID: UUID) async throws -> ClarificationProposal? { nil }
    func captures(disposition: Disposition) async throws -> [RawCapture] { [] }
    func intention(id: UUID) async throws -> Intention? {
        if failReads { throw ReadFailure() }
        return intentionValue.id == id ? intentionValue : nil
    }
    func openIntentions() async throws -> [Intention] {
        if failReads { throw ReadFailure() }
        return [intentionValue]
    }
    func focusSession(id: UUID) async throws -> FocusSession? {
        if failReads { throw ReadFailure() }
        return sessionValue?.id == id ? sessionValue : nil
    }
    func focusSessions() async throws -> [FocusSession] {
        if failReads { throw ReadFailure() }
        return sessionValue.map { [$0] } ?? []
    }
}

private struct AppModelUnusedClarifier: ClarificationProvider {
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

@MainActor
@Test func focusCommandReportsRefreshFailureAndKeepsPublishedProjectionStable() async throws {
    let id = UUID()
    let intention = Intention(
        id: id,
        sourceCaptureID: id,
        desiredOutcome: "Keep the visible state stable",
        nextAction: "Begin",
        state: .open,
        createdAt: Date(timeIntervalSince1970: 1),
        returnPacket: nil
    )
    let repository = RefreshFailingRepository(intention: intention)
    let model = AppModel(
        loop: ThoughtLoop(repository: repository, clarifier: AppModelUnusedClarifier()),
        readModels: ThoughtReadModels(repository: repository),
        focusLoop: FocusLoop(repository: repository)
    )
    #expect(await model.refresh())
    let originalProjection = model.now

    let displayed = await model.startFocus(id)

    #expect(displayed == false)
    #expect(model.commandError != nil)
    #expect(model.now == originalProjection)
}
