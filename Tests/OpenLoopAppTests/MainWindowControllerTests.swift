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

private actor ReviewWindowRepository: ThoughtRepository {
    private var storedCaptures: [UUID: RawCapture] = [:]

    func save(capture: RawCapture) async throws { storedCaptures[capture.id] = capture }
    func capture(id: UUID) async throws -> RawCapture? { storedCaptures[id] }
    func save(proposal: ClarificationProposal) async throws {}
    func save(intention: Intention) async throws {}
    func proposal(captureID: UUID) async throws -> ClarificationProposal? { nil }
    func captures(disposition: Disposition) async throws -> [RawCapture] { [] }
    func unclarifiedCaptures() async throws -> [RawCapture] { Array(storedCaptures.values) }
    func intention(id: UUID) async throws -> Intention? { nil }
    func openIntentions() async throws -> [Intention] { [] }
    func allCaptures() async throws -> [RawCapture] { Array(storedCaptures.values) }
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

private actor EnabledWindowContextTrail: ContextTrailProviding {
    func settings() async throws -> ContextTrailSettings {
        ContextTrailSettings(mode: .focusTrail)
    }
    func setEnabled(_ enabled: Bool) async throws -> ContextTrailSettings {
        ContextTrailSettings(mode: enabled ? .focusTrail : .privateMode)
    }
    func observe(
        _ application: ApplicationContext,
        at date: Date
    ) async throws -> ContextTrailEvent? { nil }
    func currentEpisodes(at date: Date) async throws -> [ContextEpisode] { [] }
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

@MainActor
@Test func laterWindowShowsCaptureReviewSurface() async throws {
    let repository = ReviewWindowRepository()
    let capture = try RawCapture(createdAt: .now, text: "Decide whether to revisit onboarding")
    try await repository.save(capture: capture)
    let model = AppModel(
        loop: ThoughtLoop(repository: repository, clarifier: WindowUnusedClarifier()),
        readModels: ThoughtReadModels(repository: repository)
    )
    _ = await model.refresh()
    let controller = MainWindowController(model: model)

    controller.show(tab: 2)
    await Task.yield()
    await Task.yield()

    #expect(controller.selectedTabForTesting == 2)
    #expect(controller.isVisibleForTesting)
    #expect(model.reviewItems.map(\.id) == [capture.id])
    controller.closeForTesting()
}

@Test func dictationUsesControlOptionSpaceWithoutOverlappingOtherGlobalBindings() {
    #expect(GlobalHotKeyBinding.quickCapture.id == 1)
    #expect(GlobalHotKeyBinding.voiceCapture.id == 2)
    #expect(GlobalHotKeyBinding.recall.id == 3)
    #expect(GlobalHotKeyBinding.voiceCapture.keyCode == GlobalHotKeyBinding.quickCapture.keyCode)
    #expect(GlobalHotKeyBinding.voiceCapture.modifiers != GlobalHotKeyBinding.quickCapture.modifiers)
    #expect(GlobalHotKeyBinding.recall.modifiers == GlobalHotKeyBinding.quickCapture.modifiers)
}

@Test func contextTrailMenuCopyMakesTheActivePrivacyModeExplicit() {
    #expect(ContextTrailMenuPresentation.title(for: .privateMode) == "Private Mode — on")
    #expect(ContextTrailMenuPresentation.title(for: .focusTrail) == "Focus Context — on")
}

@MainActor
@Test func nowWindowRendersEnabledContextEmptyState() async {
    let repository = EmptyWindowRepository()
    let model = AppModel(
        loop: ThoughtLoop(repository: repository, clarifier: WindowUnusedClarifier()),
        readModels: ThoughtReadModels(repository: repository),
        contextTrail: EnabledWindowContextTrail()
    )
    await model.refreshContextTrail()
    let controller = MainWindowController(model: model)
    #expect(controller.contentSizeForTesting.width == 980)

    controller.show(tab: 0)
    await Task.yield()

    #expect(model.contextTrailSettings.mode == .focusTrail)
    #expect(controller.selectedTabForTesting == 0)
    #expect(controller.isVisibleForTesting)
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

@MainActor
@Test func advancedModePreferencePersistsAcrossAppModels() {
    let suiteName = "OpenLoopAppTests.AdvancedMode.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let repository = EmptyWindowRepository()
    let loop = ThoughtLoop(repository: repository, clarifier: WindowUnusedClarifier())
    let key = "advanced-mode"

    let first = AppModel(
        loop: loop,
        readModels: ThoughtReadModels(repository: repository),
        defaults: defaults,
        advancedModeKey: key
    )
    #expect(first.isAdvancedModeEnabled == false)

    first.setAdvancedModeEnabled(true)

    let second = AppModel(
        loop: loop,
        readModels: ThoughtReadModels(repository: repository),
        defaults: defaults,
        advancedModeKey: key
    )
    #expect(second.isAdvancedModeEnabled)
}

@MainActor
@Test func appearancePreferencePersistsAcrossAppModels() {
    let suiteName = "OpenLoopAppTests.Appearance.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let repository = EmptyWindowRepository()
    let loop = ThoughtLoop(repository: repository, clarifier: WindowUnusedClarifier())
    let key = "appearance"

    let first = AppModel(
        loop: loop,
        readModels: ThoughtReadModels(repository: repository),
        defaults: defaults,
        appearanceModeKey: key
    )
    #expect(first.appearanceMode == .system)

    first.setAppearanceMode(.light)

    let second = AppModel(
        loop: loop,
        readModels: ThoughtReadModels(repository: repository),
        defaults: defaults,
        appearanceModeKey: key
    )
    #expect(second.appearanceMode == .light)
}

@MainActor
@Test func meetingLanguageAlwaysStartsWithAutomaticDetection() {
    let suiteName = "OpenLoopAppTests.MeetingLanguage.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let repository = EmptyWindowRepository()
    let loop = ThoughtLoop(repository: repository, clarifier: WindowUnusedClarifier())
    defaults.set(MeetingLanguagePreference.hindiHinglish.rawValue, forKey: "OpenLoopMeetingLanguage")

    let first = AppModel(
        loop: loop,
        readModels: ThoughtReadModels(repository: repository),
        defaults: defaults
    )
    #expect(first.meetingLanguagePreference == .automatic)

    first.setMeetingLanguagePreference(.hindiHinglish)
    #expect(first.meetingLanguagePreference == .hindiHinglish)

    let second = AppModel(
        loop: loop,
        readModels: ThoughtReadModels(repository: repository),
        defaults: defaults
    )
    #expect(second.meetingLanguagePreference == .automatic)
}
