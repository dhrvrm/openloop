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

private actor WindowMemoryCompiler: WorkingMemoryCompiling {
    private(set) var calls = 0
    func compile() async throws -> [MemoryRecord] {
        calls += 1
        return []
    }
}

@MainActor
@Test func mainWorkspaceShowsTheRequestedSurfaceInARealWindow() async {
    let repository = EmptyWindowRepository()
    let memoryCompiler = WindowMemoryCompiler()
    let model = AppModel(
        loop: ThoughtLoop(repository: repository, clarifier: WindowUnusedClarifier()),
        readModels: ThoughtReadModels(repository: repository),
        workingMemory: memoryCompiler
    )
    let controller = MainWindowController(model: model)

    controller.show(tab: 3)
    await Task.yield()
    await Task.yield()

    #expect(controller.selectedTabForTesting == 3)
    #expect(controller.isVisibleForTesting)
    #expect(controller.windowNumberForTesting > 0)
    #expect(await memoryCompiler.calls == 1)
    controller.closeForTesting()
}

@Test func recallUsesADistinctCommandShiftFBinding() {
    #expect(GlobalHotKeyBinding.quickCapture.id == 1)
    #expect(GlobalHotKeyBinding.voiceCapture.id == 2)
    #expect(GlobalHotKeyBinding.recall.id == 3)
    #expect(GlobalHotKeyBinding.recall.keyCode != GlobalHotKeyBinding.voiceCapture.keyCode)
    #expect(GlobalHotKeyBinding.recall.modifiers == GlobalHotKeyBinding.quickCapture.modifiers)
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
