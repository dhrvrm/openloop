import Foundation
import Testing
@testable import ADHDCore

private actor FocusRepository: ThoughtRepository {
    var intentions: [UUID: Intention] = [:]
    var sessions: [UUID: FocusSession] = [:]
    var combinedSaveCount = 0

    func save(capture: RawCapture) async throws {}
    func save(proposal: ClarificationProposal) async throws {}
    func save(intention: Intention) async throws { intentions[intention.id] = intention }
    func save(focusSession: FocusSession) async throws { sessions[focusSession.id] = focusSession }
    func save(intention: Intention, focusSession: FocusSession) async throws {
        intentions[intention.id] = intention
        sessions[focusSession.id] = focusSession
        combinedSaveCount += 1
    }
    func proposal(captureID: UUID) async throws -> ClarificationProposal? { nil }
    func captures(disposition: Disposition) async throws -> [RawCapture] { [] }
    func intention(id: UUID) async throws -> Intention? { intentions[id] }
    func openIntentions() async throws -> [Intention] { Array(intentions.values) }
    func focusSession(id: UUID) async throws -> FocusSession? { sessions[id] }
    func focusSessions() async throws -> [FocusSession] { Array(sessions.values) }

    func insert(_ intention: Intention) { intentions[intention.id] = intention }
    func savedPairCount() -> Int { combinedSaveCount }
}

private actor LegacyFocusUnsupportedRepository: ThoughtRepository {
    var storedIntention: Intention

    init(intention: Intention) { storedIntention = intention }

    func save(capture: RawCapture) async throws {}
    func save(proposal: ClarificationProposal) async throws {}
    func save(intention: Intention) async throws { storedIntention = intention }
    func proposal(captureID: UUID) async throws -> ClarificationProposal? { nil }
    func captures(disposition: Disposition) async throws -> [RawCapture] { [] }
    func intention(id: UUID) async throws -> Intention? {
        storedIntention.id == id ? storedIntention : nil
    }
    func openIntentions() async throws -> [Intention] { [storedIntention] }
}

private let focusStart = Date(timeIntervalSince1970: 2_000)

private func makeIntention(id: UUID = UUID(), createdAt: Date = focusStart) -> Intention {
    Intention(
        id: id,
        sourceCaptureID: id,
        desiredOutcome: "Send the revised flow",
        nextAction: "Open the draft",
        state: .open,
        createdAt: createdAt,
        returnPacket: nil
    )
}

private func makeLegacyInterruptedIntention() throws -> Intention {
    let id = UUID()
    return Intention(
        id: id,
        sourceCaptureID: id,
        desiredOutcome: "Resume legacy work",
        nextAction: "Old next action",
        state: .interrupted,
        createdAt: focusStart,
        returnPacket: try ReturnPacket(
            capturedAt: focusStart.addingTimeInterval(10),
            justCompleted: "Saved before focus sessions existed",
            nextAction: "Recovered exact next action",
            blocker: nil,
            references: ["legacy reference"]
        )
    )
}

@Test func startingFocusActivatesIntentionAndPersistsOnePair() async throws {
    let repository = FocusRepository()
    let intention = makeIntention()
    await repository.insert(intention)
    let loop = FocusLoop(repository: repository)

    let update = try await loop.start(intention.id, at: focusStart)

    #expect(update.intention.state == .active)
    #expect(update.session.intentionID == intention.id)
    #expect(update.session.state == .active)
    #expect(await repository.savedPairCount() == 1)
}

@Test func secondCurrentFocusIsRejected() async throws {
    let repository = FocusRepository()
    let first = makeIntention()
    let second = makeIntention(createdAt: focusStart.addingTimeInterval(1))
    await repository.insert(first)
    await repository.insert(second)
    let loop = FocusLoop(repository: repository)
    _ = try await loop.start(first.id, at: focusStart)

    await #expect(throws: FocusLoopError.currentFocusExists(first.id)) {
        try await loop.start(second.id, at: focusStart.addingTimeInterval(2))
    }
}

@Test func focusCanPauseAndContinueWithPersistedElapsedTime() async throws {
    let repository = FocusRepository()
    let intention = makeIntention()
    await repository.insert(intention)
    let loop = FocusLoop(repository: repository)
    _ = try await loop.start(intention.id, at: focusStart)

    let paused = try await loop.pause(intention.id, at: focusStart.addingTimeInterval(30))
    let continued = try await loop.continueSession(
        intention.id,
        at: focusStart.addingTimeInterval(50)
    )

    #expect(paused.session.state == .paused)
    #expect(paused.session.accumulatedSeconds == 30)
    #expect(continued.session.state == .active)
    #expect(continued.session.accumulatedSeconds == 30)
    #expect(await repository.savedPairCount() == 3)
}

@Test func interruptionPersistsTheExactPacketAndBothInterruptedStates() async throws {
    let repository = FocusRepository()
    let intention = makeIntention()
    await repository.insert(intention)
    let loop = FocusLoop(repository: repository)
    _ = try await loop.start(intention.id, at: focusStart)
    let interruptedAt = focusStart.addingTimeInterval(60)
    let draft = InterruptionDraft(
        justCompleted: "Opened the draft",
        nextAction: "Replace the first screenshot",
        blocker: "Need the new asset",
        references: ["/tmp/flow.md", "https://example.test/asset"]
    )

    let update = try await loop.interrupt(intention.id, draft: draft, at: interruptedAt)

    #expect(update.intention.state == .interrupted)
    #expect(update.session.state == .interrupted)
    #expect(update.intention.returnPacket?.capturedAt == interruptedAt)
    #expect(update.intention.returnPacket?.justCompleted == draft.justCompleted)
    #expect(update.intention.returnPacket?.nextAction == draft.nextAction)
    #expect(update.intention.returnPacket?.blocker == draft.blocker)
    #expect(update.intention.returnPacket?.references == draft.references)
    #expect(await repository.savedPairCount() == 2)
}

@Test func resumeRestoresPacketNextActionAndFinishClosesBothValues() async throws {
    let repository = FocusRepository()
    let intention = makeIntention()
    await repository.insert(intention)
    let loop = FocusLoop(repository: repository)
    _ = try await loop.start(intention.id, at: focusStart)
    _ = try await loop.interrupt(
        intention.id,
        draft: InterruptionDraft(
            justCompleted: nil,
            nextAction: "Continue from the saved line",
            blocker: nil,
            references: []
        ),
        at: focusStart.addingTimeInterval(10)
    )

    let resumed = try await loop.resume(intention.id, at: focusStart.addingTimeInterval(20))
    let finished = try await loop.finish(intention.id, at: focusStart.addingTimeInterval(25))

    #expect(resumed.intention.nextAction == "Continue from the saved line")
    #expect(resumed.session.state == .active)
    #expect(finished.intention.state == .closed)
    #expect(finished.session.state == .finished)
}

@Test func missingFocusValuesProduceTypedErrors() async {
    let repository = FocusRepository()
    let missing = UUID()
    let loop = FocusLoop(repository: repository)

    await #expect(throws: FocusLoopError.intentionNotFound(missing)) {
        try await loop.start(missing, at: .now)
    }

    let intention = makeIntention()
    await repository.insert(intention)
    await #expect(throws: FocusLoopError.focusSessionNotFound(intention.id)) {
        try await loop.pause(intention.id, at: .now)
    }
}

@Test func legacyActiveIntentionCanStartAFocusSession() async throws {
    let repository = FocusRepository()
    var intention = makeIntention()
    try intention.transition(to: .active)
    await repository.insert(intention)
    let loop = FocusLoop(repository: repository)

    let update = try await loop.start(intention.id, at: focusStart)

    #expect(update.intention.state == .active)
    #expect(update.session.state == .active)
}

@Test func legacyInterruptedIntentionCanResumeWithoutAnExistingSession() async throws {
    let repository = FocusRepository()
    let intention = try makeLegacyInterruptedIntention()
    await repository.insert(intention)
    let loop = FocusLoop(repository: repository)

    let update = try await loop.resume(intention.id, at: focusStart.addingTimeInterval(20))

    #expect(update.intention.state == .active)
    #expect(update.intention.nextAction == "Recovered exact next action")
    #expect(update.session.state == .active)
    #expect(update.session.intentionID == intention.id)
}

@Test func legacyInterruptedIntentionCanFinishWithoutAnExistingSession() async throws {
    let repository = FocusRepository()
    let intention = try makeLegacyInterruptedIntention()
    await repository.insert(intention)
    let loop = FocusLoop(repository: repository)

    let update = try await loop.finish(intention.id, at: focusStart.addingTimeInterval(20))

    #expect(update.intention.state == .closed)
    #expect(update.session.state == .finished)
    #expect(update.session.intentionID == intention.id)
}

@Test func unsupportedRepositoryRejectsFocusBeforeSavingTheIntention() async throws {
    let intention = makeIntention()
    let repository = LegacyFocusUnsupportedRepository(intention: intention)
    let loop = FocusLoop(repository: repository)

    await #expect(throws: ThoughtRepositoryCompatibilityError.focusSessionsUnsupported) {
        try await loop.start(intention.id, at: focusStart)
    }

    #expect(try await repository.intention(id: intention.id)?.state == .open)
}

@Test func openIntentionCannotFinishWithoutFirstEnteringFocus() async throws {
    let repository = FocusRepository()
    let intention = makeIntention()
    await repository.insert(intention)
    let loop = FocusLoop(repository: repository)

    await #expect(throws: FocusLoopError.focusSessionNotFound(intention.id)) {
        try await loop.finish(intention.id, at: focusStart)
    }
}
