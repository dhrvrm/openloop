import ADHDCore
import Foundation
import Testing
@testable import OpenLoopApp

private actor ContextTrailProbe: ContextTrailProviding {
    enum Failure: Error { case unavailable }
    private var settingsValue = ContextTrailSettings()
    private var episodesValue: [ContextEpisode] = []
    private(set) var observations: [ApplicationContext] = []
    var fail = false

    func settings() async throws -> ContextTrailSettings {
        if fail { throw Failure.unavailable }
        return settingsValue
    }

    func setEnabled(_ enabled: Bool) async throws -> ContextTrailSettings {
        if fail { throw Failure.unavailable }
        settingsValue = ContextTrailSettings(mode: enabled ? .focusTrail : .privateMode)
        if !enabled {
            observations = []
            episodesValue = []
        }
        return settingsValue
    }

    func observe(
        _ application: ApplicationContext,
        at date: Date
    ) async throws -> ContextTrailEvent? {
        if fail { throw Failure.unavailable }
        guard settingsValue.isEnabled else { return nil }
        observations.append(application)
        let event = ContextTrailEvent(
            intentionID: UUID(),
            focusSessionID: UUID(),
            observedAt: date,
            application: application
        )
        episodesValue = [ContextEpisode(
            id: event.id,
            focusSessionID: event.focusSessionID,
            application: application,
            startedAt: date,
            lastObservedAt: date,
            observationCount: 1
        )]
        return event
    }

    func currentEpisodes(at date: Date) async throws -> [ContextEpisode] {
        if fail { throw Failure.unavailable }
        return episodesValue
    }

    func setFailure(_ value: Bool) { fail = value }
}

@MainActor
@Test func appModelControlsAndPublishesExplicitContextTrail() async throws {
    let probe = ContextTrailProbe()
    let model = contextTrailTestModel(probe)
    let safari = try ApplicationContext(
        bundleIdentifier: "com.apple.safari",
        applicationName: "Safari"
    )

    await model.observeApplication(safari, at: Date(timeIntervalSince1970: 1))
    #expect(model.currentApplication == safari)
    #expect(await probe.observations.isEmpty)

    await model.setContextTrailEnabled(true, at: Date(timeIntervalSince1970: 2))
    #expect(model.contextTrailSettings.mode == .focusTrail)
    #expect(model.contextEpisodes.map(\.application) == [safari])
    #expect(await probe.observations == [safari])

    await model.setContextTrailEnabled(false, at: Date(timeIntervalSince1970: 3))
    #expect(model.contextTrailSettings.mode == .privateMode)
    #expect(model.contextEpisodes.isEmpty)
    #expect(model.contextTrailError == nil)
}

@MainActor
@Test func appModelContainsContextTrailFailureAndKeepsPriorEpisodes() async throws {
    let probe = ContextTrailProbe()
    let model = contextTrailTestModel(probe)
    let editor = try ApplicationContext(
        bundleIdentifier: "dev.editor",
        applicationName: "Editor"
    )
    await model.observeApplication(editor)
    await model.setContextTrailEnabled(true)
    let prior = model.contextEpisodes
    await probe.setFailure(true)

    await model.refreshContextTrail()

    #expect(model.contextEpisodes == prior)
    #expect(model.contextTrailError == "Context trail paused. Focus and capture remain safe.")
    #expect(model.captureError == nil)
    #expect(model.commandError == nil)
    #expect(model.recallError == nil)
}

@MainActor
private func contextTrailTestModel(_ trail: any ContextTrailProviding) -> AppModel {
    let repository = ContextTrailAppRepository()
    return AppModel(
        loop: ThoughtLoop(repository: repository, clarifier: ContextTrailUnusedClarifier()),
        readModels: ThoughtReadModels(repository: repository),
        contextTrail: trail
    )
}

private actor ContextTrailAppRepository: ThoughtRepository {
    func save(capture: RawCapture) async throws {}
    func save(proposal: ClarificationProposal) async throws {}
    func save(intention: Intention) async throws {}
    func captures(disposition: Disposition) async throws -> [RawCapture] { [] }
    func intention(id: UUID) async throws -> Intention? { nil }
    func openIntentions() async throws -> [Intention] { [] }
    func proposal(captureID: UUID) async throws -> ClarificationProposal? { nil }
}

private struct ContextTrailUnusedClarifier: ClarificationProvider {
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
