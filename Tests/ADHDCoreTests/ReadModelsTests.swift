import Foundation
import Testing
@testable import ADHDCore

private actor ReadRepository: ThoughtRepository {
    var storedCaptures: [UUID: RawCapture] = [:]
    var storedProposals: [UUID: ClarificationProposal] = [:]
    var storedIntentions: [UUID: Intention] = [:]
    var storedFocusSessions: [UUID: FocusSession] = [:]

    func save(capture: RawCapture) async throws { storedCaptures[capture.id] = capture }
    func save(proposal: ClarificationProposal) async throws {
        storedProposals[proposal.captureID] = proposal
    }
    func save(intention: Intention) async throws { storedIntentions[intention.id] = intention }
    func save(focusSession: FocusSession) async throws {
        storedFocusSessions[focusSession.id] = focusSession
    }
    func save(intention: Intention, focusSession: FocusSession) async throws {
        storedIntentions[intention.id] = intention
        storedFocusSessions[focusSession.id] = focusSession
    }
    func proposal(captureID: UUID) async throws -> ClarificationProposal? {
        storedProposals[captureID]
    }
    func captures(disposition: Disposition) async throws -> [RawCapture] {
        storedCaptures.values.filter { storedProposals[$0.id]?.disposition == disposition }
    }
    func unclarifiedCaptures() async throws -> [RawCapture] {
        storedCaptures.values.filter { storedProposals[$0.id] == nil }
    }
    func intention(id: UUID) async throws -> Intention? { storedIntentions[id] }
    func openIntentions() async throws -> [Intention] {
        storedIntentions.values.filter { $0.state != .closed && $0.state != .released }
    }
    func focusSession(id: UUID) async throws -> FocusSession? { storedFocusSessions[id] }
    func focusSessions() async throws -> [FocusSession] { Array(storedFocusSessions.values) }
}

@Test func nowPrefersAnActiveIntention() async throws {
    let repository = ReadRepository()
    let captureID = UUID()
    let olderOpen = Intention(
        id: UUID(), sourceCaptureID: captureID, desiredOutcome: "Older",
        nextAction: "Wait", state: .open, createdAt: Date(timeIntervalSince1970: 1),
        returnPacket: nil
    )
    let active = Intention(
        id: UUID(), sourceCaptureID: captureID, desiredOutcome: "Current",
        nextAction: "Begin", state: .active, createdAt: Date(timeIntervalSince1970: 2),
        returnPacket: nil
    )
    try await repository.save(intention: olderOpen)
    try await repository.save(intention: active)

    let item = try await ThoughtReadModels(repository: repository).now()

    #expect(item?.intentionID == active.id)
    #expect(item?.nextAction == "Begin")
}

@Test func laterIncludesSafeNonActionDispositionsAndExcludesRelease() async throws {
    let repository = ReadRepository()
    let models = ThoughtReadModels(repository: repository)
    let dispositions: [Disposition] = [.later, .memory, .unclear, .release]

    let pending = try RawCapture(
        createdAt: Date(timeIntervalSince1970: -1),
        text: "pending clarification"
    )
    try await repository.save(capture: pending)

    for (index, disposition) in dispositions.enumerated() {
        let capture = try RawCapture(
            createdAt: Date(timeIntervalSince1970: Double(index)),
            text: disposition.rawValue
        )
        let proposal = try ClarificationProposal(
            captureID: capture.id, disposition: disposition, desiredOutcome: nil,
            nextAction: nil, confidence: 1
        )
        try await repository.save(capture: capture)
        try await repository.save(proposal: proposal)
    }

    let items = try await models.later()

    #expect(items.map(\.disposition) == [.unclear, .later, .memory, .unclear])
    #expect(items.map(\.text) == ["pending clarification", "later", "memory", "unclear"])
}

@Test func nowExposesStartableOpenIntentionWithoutFocusTiming() async throws {
    let repository = ReadRepository()
    let intention = Intention(
        id: UUID(), sourceCaptureID: UUID(), desiredOutcome: "Start calmly",
        nextAction: "Open the outline", state: .open,
        createdAt: Date(timeIntervalSince1970: 1), returnPacket: nil
    )
    try await repository.save(intention: intention)

    let item = try await ThoughtReadModels(repository: repository).now()

    #expect(item?.intentionID == intention.id)
    #expect(item?.focus == nil)
}

@Test func nowJoinsCurrentFocusAndCalculatesElapsedTime() async throws {
    let repository = ReadRepository()
    let startedAt = Date(timeIntervalSince1970: 100)
    let current = Intention(
        id: UUID(), sourceCaptureID: UUID(), desiredOutcome: "Current",
        nextAction: "Keep writing", state: .active, createdAt: startedAt,
        returnPacket: nil
    )
    let unrelated = Intention(
        id: UUID(), sourceCaptureID: UUID(), desiredOutcome: "Unrelated",
        nextAction: "Wait", state: .open,
        createdAt: startedAt.addingTimeInterval(-10), returnPacket: nil
    )
    let session = FocusSession(
        id: UUID(), intentionID: current.id, startedAt: startedAt
    )
    try await repository.save(intention: current, focusSession: session)
    try await repository.save(intention: unrelated)

    let item = try await ThoughtReadModels(repository: repository).now()

    #expect(item?.intentionID == current.id)
    #expect(item?.focus?.state == .active)
    #expect(item?.elapsed(at: startedAt.addingTimeInterval(95)) == 95)
}

@Test func interruptedIntentionsLeaveNowAndAppearInReturnNewestFirst() async throws {
    let repository = ReadRepository()
    let olderDate = Date(timeIntervalSince1970: 100)
    let newerDate = Date(timeIntervalSince1970: 200)
    let older = try interruptedIntention(capturedAt: olderDate, marker: "older")
    let newer = try interruptedIntention(capturedAt: newerDate, marker: "newer")
    try await repository.save(intention: older)
    try await repository.save(intention: newer)
    let models = ThoughtReadModels(repository: repository)

    let now = try await models.now()
    let returns = try await models.returns()

    #expect(now == nil)
    #expect(returns.map(\.intentionID) == [newer.id, older.id])
    #expect(returns[0].desiredOutcome == "newer outcome")
    #expect(returns[0].justCompleted == "newer completed")
    #expect(returns[0].nextAction == "newer next")
    #expect(returns[0].blocker == "newer blocker")
    #expect(returns[0].references == ["newer reference"])
    #expect(returns[0].capturedAt == newerDate)
}

@Test func openLoopLibraryExposesEveryUnfinishedIntentionInCalmStateOrder() async throws {
    let repository = ReadRepository()
    let createdAt = Date(timeIntervalSince1970: 50)
    let active = Intention(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        sourceCaptureID: UUID(), desiredOutcome: "Active outcome",
        nextAction: "Active next", state: .active, createdAt: createdAt,
        returnPacket: nil
    )
    let openFirst = Intention(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        sourceCaptureID: UUID(), desiredOutcome: "Open first",
        nextAction: "First next", state: .open, createdAt: createdAt,
        returnPacket: nil
    )
    let openSecond = Intention(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        sourceCaptureID: UUID(), desiredOutcome: "Open second",
        nextAction: "Second next", state: .open, createdAt: createdAt,
        returnPacket: nil
    )
    let interrupted = try interruptedIntention(
        capturedAt: createdAt.addingTimeInterval(20), marker: "Interrupted"
    )
    let closed = Intention(
        id: UUID(), sourceCaptureID: UUID(), desiredOutcome: "Closed",
        nextAction: "Done", state: .closed, createdAt: createdAt,
        returnPacket: nil
    )
    let released = Intention(
        id: UUID(), sourceCaptureID: UUID(), desiredOutcome: "Released",
        nextAction: "Drop", state: .released, createdAt: createdAt,
        returnPacket: nil
    )
    for intention in [openSecond, interrupted, released, active, closed, openFirst] {
        try await repository.save(intention: intention)
    }

    let items = try await ThoughtReadModels(repository: repository).openLoops()

    #expect(items.map(\.intentionID) == [active.id, openFirst.id, openSecond.id, interrupted.id])
    #expect(items.map(\.state) == [.active, .open, .open, .interrupted])
    #expect(items[0].desiredOutcome == "Active outcome")
    #expect(items[0].nextAction == "Active next")
    #expect(items[0].createdAt == createdAt)
}

private func interruptedIntention(capturedAt: Date, marker: String) throws -> Intention {
    let id = UUID()
    let packet = try ReturnPacket(
        capturedAt: capturedAt,
        justCompleted: "\(marker) completed",
        nextAction: "\(marker) next",
        blocker: "\(marker) blocker",
        references: ["\(marker) reference"]
    )
    return Intention(
        id: id,
        sourceCaptureID: id,
        desiredOutcome: "\(marker) outcome",
        nextAction: "original",
        state: .interrupted,
        createdAt: capturedAt.addingTimeInterval(-10),
        returnPacket: packet
    )
}
