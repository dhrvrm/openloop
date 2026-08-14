import ADHDCore
import Foundation
import Testing
@testable import OpenLoopApp

private actor FailingCaptureRepository: ThoughtRepository {
    struct SaveFailure: Error {}

    func save(capture: RawCapture) async throws { throw SaveFailure() }
    func save(proposal: ClarificationProposal) async throws {}
    func save(intention: Intention) async throws {}
    func proposal(captureID: UUID) async throws -> ClarificationProposal? { nil }
    func captures(disposition: Disposition) async throws -> [RawCapture] { [] }
    func intention(id: UUID) async throws -> Intention? { nil }
    func openIntentions() async throws -> [Intention] { [] }
}

private struct UnusedClarifier: ClarificationProvider {
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
@Test func failedSaveKeepsTheTypedCaptureVisible() async {
    let repository = FailingCaptureRepository()
    let model = AppModel(
        loop: ThoughtLoop(repository: repository, clarifier: UnusedClarifier()),
        readModels: ThoughtReadModels(repository: repository)
    )
    let controller = QuickCaptureController(model: model)
    controller.textForTesting = "do not lose this"
    let previousCount = controller.latency.samples.count
    controller.show()
    #expect(await controller.waitForSample(after: previousCount))

    let saved = await controller.submitCurrentText()

    #expect(saved == false)
    #expect(controller.textForTesting == "do not lose this")
    #expect(model.captureError != nil)
    #expect(controller.isOnscreenForTesting)
    controller.hide()
}
