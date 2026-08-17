import ADHDCore
import Foundation
import Testing
@testable import OpenLoopApp

private actor AppResurfacingRepository: ThoughtRepository {
    struct ResurfacingFailure: Error {}

    var intentions: [UUID: Intention] = [:]
    var focus: [UUID: FocusSession] = [:]
    var rules: [UUID: ResurfacingRule] = [:]
    var events: [UUID: SuggestionEvent] = [:]
    var failResurfacingWrites = false

    func save(capture: RawCapture) async throws {}
    func save(proposal: ClarificationProposal) async throws {}
    func save(intention: Intention) async throws { intentions[intention.id] = intention }
    func save(focusSession: FocusSession) async throws { focus[focusSession.id] = focusSession }
    func save(intention: Intention, focusSession: FocusSession) async throws {
        intentions[intention.id] = intention
        focus[focusSession.id] = focusSession
    }
    func proposal(captureID: UUID) async throws -> ClarificationProposal? { nil }
    func captures(disposition: Disposition) async throws -> [RawCapture] { [] }
    func intention(id: UUID) async throws -> Intention? { intentions[id] }
    func openIntentions() async throws -> [Intention] {
        intentions.values.filter { $0.state != .closed && $0.state != .released }
    }
    func focusSession(id: UUID) async throws -> FocusSession? { focus[id] }
    func focusSessions() async throws -> [FocusSession] { Array(focus.values) }
    func save(resurfacingRule: ResurfacingRule) async throws {
        if failResurfacingWrites { throw ResurfacingFailure() }
        rules[resurfacingRule.intentionID] = resurfacingRule
    }
    func deleteResurfacingRule(intentionID: UUID) async throws {
        if failResurfacingWrites { throw ResurfacingFailure() }
        rules[intentionID] = nil
    }
    func resurfacingRules() async throws -> [ResurfacingRule] { Array(rules.values) }
    func append(suggestionEvent: SuggestionEvent) async throws {
        if failResurfacingWrites { throw ResurfacingFailure() }
        events[suggestionEvent.id] = suggestionEvent
    }
    func suggestionEvents() async throws -> [SuggestionEvent] {
        events.values.sorted { $0.occurredAt < $1.occurredAt }
    }

    func setFailResurfacingWrites(_ value: Bool) { failResurfacingWrites = value }
}

private struct ResurfacingUnusedClarifier: ClarificationProvider {
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
@Test func appModelLinksAndUnlinksAnOpenLoopToCurrentApplication() async throws {
    let (model, repository, intention) = try await resurfacingModel()
    let application = try ApplicationContext(
        bundleIdentifier: "dev.openloop.Editor", applicationName: "Editor"
    )
    let date = Date(timeIntervalSince1970: 1_000)
    await model.refreshContext(application, at: date)

    #expect(await model.linkSuggestion(intention.id, to: application, at: date))
    #expect(model.isLinked(intention.id, to: application))
    #expect(model.suggestions.map(\.intentionID) == [intention.id])
    #expect(try await repository.resurfacingRules().count == 1)

    #expect(await model.unlinkSuggestion(intention.id))
    #expect(model.isLinked(intention.id, to: application) == false)
    #expect(model.suggestions.isEmpty)
    #expect(try await repository.resurfacingRules().isEmpty)
}

@MainActor
@Test func suggestionStartBeginsFocusAndLaterOrNeverDismissInOneAction() async throws {
    let application = try ApplicationContext(
        bundleIdentifier: "dev.openloop.Editor", applicationName: "Editor"
    )
    let date = Date(timeIntervalSince1970: 2_000)

    let (startModel, startRepository, startIntention) = try await resurfacingModel()
    await startModel.refreshContext(application, at: date)
    #expect(await startModel.linkSuggestion(startIntention.id, to: application, at: date))
    #expect(await startModel.startSuggestion(startIntention.id, at: date.addingTimeInterval(1)))
    #expect(startModel.suggestions.isEmpty)
    #expect(try await startRepository.intention(id: startIntention.id)?.state == .active)
    #expect(try await startRepository.suggestionEvents().contains { $0.kind == .started })

    let (laterModel, laterRepository, laterIntention) = try await resurfacingModel()
    await laterModel.refreshContext(application, at: date)
    #expect(await laterModel.linkSuggestion(laterIntention.id, to: application, at: date))
    #expect(await laterModel.deferSuggestion(laterIntention.id, at: date.addingTimeInterval(1)))
    #expect(laterModel.suggestions.isEmpty)
    #expect(try await laterRepository.suggestionEvents().contains { $0.kind == .later })

    let (neverModel, neverRepository, neverIntention) = try await resurfacingModel()
    await neverModel.refreshContext(application, at: date)
    #expect(await neverModel.linkSuggestion(neverIntention.id, to: application, at: date))
    #expect(await neverModel.silenceSuggestion(neverIntention.id, at: date.addingTimeInterval(1)))
    #expect(neverModel.suggestions.isEmpty)
    #expect(try await neverRepository.suggestionEvents().contains { $0.kind == .never })
}

@MainActor
@Test func resurfacingWriteFailureKeepsStoredLoopsVisibleAndUsesNeutralCopy() async throws {
    let (model, repository, intention) = try await resurfacingModel()
    let application = try ApplicationContext(
        bundleIdentifier: "dev.openloop.Editor", applicationName: "Editor"
    )
    await repository.setFailResurfacingWrites(true)

    let linked = await model.linkSuggestion(intention.id, to: application, at: .now)

    #expect(linked == false)
    #expect(model.openLoops.map(\.intentionID) == [intention.id])
    #expect(model.resurfacingError == "That context preference could not be saved. Your open loop is safe.")
}

@MainActor
private func resurfacingModel() async throws -> (
    AppModel,
    AppResurfacingRepository,
    Intention
) {
    let repository = AppResurfacingRepository()
    let intention = Intention(
        id: UUID(), sourceCaptureID: UUID(), desiredOutcome: "Ship the visible GUI",
        nextAction: "Run the native window", state: .open,
        createdAt: Date(timeIntervalSince1970: 1), returnPacket: nil
    )
    try await repository.save(intention: intention)
    let model = AppModel(
        loop: ThoughtLoop(repository: repository, clarifier: ResurfacingUnusedClarifier()),
        readModels: ThoughtReadModels(repository: repository),
        focusLoop: FocusLoop(repository: repository),
        resurfacingLoop: ResurfacingLoop(repository: repository)
    )
    _ = await model.refresh()
    return (model, repository, intention)
}
