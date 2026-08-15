import ADHDCore
import AppKit
import Foundation
import Testing
@testable import OpenLoopApp

private actor EmptyWindowRepository: ThoughtRepository {
    func save(capture: RawCapture) async throws {}
    func save(proposal: ClarificationProposal) async throws {}
    func save(intention: Intention) async throws {}
    func proposal(captureID: UUID) async throws -> ClarificationProposal? { nil }
    func captures(disposition: Disposition) async throws -> [RawCapture] { [] }
    func intention(id: UUID) async throws -> Intention? { nil }
    func openIntentions() async throws -> [Intention] { [] }
}

private struct WindowUnusedClarifier: ClarificationProvider {
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
@Test func mainWorkspaceShowsTheRequestedSurfaceInARealWindow() async {
    let repository = EmptyWindowRepository()
    let model = AppModel(
        loop: ThoughtLoop(repository: repository, clarifier: WindowUnusedClarifier()),
        readModels: ThoughtReadModels(repository: repository)
    )
    let controller = MainWindowController(model: model)

    controller.show(tab: 2)
    await Task.yield()

    #expect(controller.selectedTabForTesting == 2)
    #expect(controller.isVisibleForTesting)
    #expect(controller.windowNumberForTesting > 0)
    controller.closeForTesting()
}

@MainActor
@Test func workspaceLifecycleShowsOnLaunchAndOnlyRestoresAHiddenWindow() {
    var requestedTabs: [Int] = []
    let lifecycle = WorkspaceLifecycle { requestedTabs.append($0) }

    lifecycle.showInitialWorkspace()
    #expect(lifecycle.restoreWorkspace(hasVisibleWindows: true) == false)
    #expect(lifecycle.restoreWorkspace(hasVisibleWindows: false))

    #expect(requestedTabs == [0, 0])
}
