import Foundation
import Testing
@testable import ADHDCore

private actor MemoryRepository: ThoughtRepository {
    var captures: [UUID: RawCapture] = [:]
    var proposals: [UUID: ClarificationProposal] = [:]
    var intentions: [UUID: Intention] = [:]

    func save(capture: RawCapture) async throws { captures[capture.id] = capture }
    func save(proposal: ClarificationProposal) async throws { proposals[proposal.captureID] = proposal }
    func save(intention: Intention) async throws { intentions[intention.id] = intention }
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

    func captureCount() -> Int { captures.count }
}

private struct FixedClarifier: ClarificationProvider {
    func propose(for capture: RawCapture) async throws -> ClarificationProposal {
        try ClarificationProposal(
            captureID: capture.id,
            disposition: .action,
            desiredOutcome: "Reply to Riya",
            nextAction: "Open Riya's latest message",
            confidence: 1
        )
    }
}

private struct FailingClarifier: ClarificationProvider {
    struct Failure: Error {}

    func propose(for capture: RawCapture) async throws -> ClarificationProposal {
        throw Failure()
    }
}

private actor CountingClarifier: ClarificationProvider {
    private(set) var callCount = 0

    func propose(for capture: RawCapture) async throws -> ClarificationProposal {
        callCount += 1
        return try ClarificationProposal(
            captureID: capture.id,
            disposition: .unclear,
            desiredOutcome: nil,
            nextAction: nil,
            confidence: 1
        )
    }
}

@Test func acceptanceDoesNotWaitForClarification() async throws {
    let repository = MemoryRepository()
    let clarifier = CountingClarifier()
    let loop = ThoughtLoop(repository: repository, clarifier: clarifier)

    let capture = try await loop.accept(text: "keep this thought", at: .now)

    #expect(await repository.captures[capture.id] == capture)
    #expect(await clarifier.callCount == 0)
}

@Test func clarificationPersistsItsDecision() async throws {
    let repository = MemoryRepository()
    let loop = ThoughtLoop(repository: repository, clarifier: FixedClarifier())
    let capture = try await loop.accept(text: "reply to Riya", at: .now)

    let result = try await loop.clarify(capture)

    #expect(try await repository.proposal(captureID: capture.id) == result.proposal)
}

@Test func acceptedCaptureIsClarifiedDuringRecovery() async throws {
    let repository = MemoryRepository()
    let loop = ThoughtLoop(repository: repository, clarifier: FixedClarifier())
    let capture = try await loop.accept(text: "reply later", at: .now)

    let recovered = await loop.recoverUnclarifiedCaptures()

    #expect(recovered == 1)
    #expect(try await repository.proposal(captureID: capture.id) != nil)
    #expect(try await repository.openIntentions().count == 1)
}

@Test func capturePersistsBeforeItBecomesAnIntention() async throws {
    let repository = MemoryRepository()
    let loop = ThoughtLoop(repository: repository, clarifier: FixedClarifier())

    let result = try await loop.capture(text: "reply to Riya", at: .now)

    #expect(await repository.captures[result.capture.id] != nil)
    #expect(try await repository.proposal(captureID: result.capture.id) == result.proposal)
    #expect(result.intention?.nextAction == "Open Riya's latest message")
    #expect(try await repository.openIntentions().count == 1)
}

@Test func captureRemainsSavedWhenClarificationFails() async {
    let repository = MemoryRepository()
    let loop = ThoughtLoop(repository: repository, clarifier: FailingClarifier())

    await #expect(throws: FailingClarifier.Failure.self) {
        try await loop.capture(text: "keep this thought", at: .now)
    }
    #expect(await repository.captureCount() == 1)
}

@Test func lifecycleTransitionsArePersistedThroughTheLoop() async throws {
    let repository = MemoryRepository()
    let loop = ThoughtLoop(repository: repository, clarifier: FixedClarifier())
    let result = try await loop.capture(text: "reply to Riya", at: .now)
    let id = try #require(result.intention?.id)

    _ = try await loop.start(id)
    let packet = try ReturnPacket(
        capturedAt: .now,
        justCompleted: "Opened the message",
        nextAction: "Draft the first sentence",
        blocker: nil,
        references: []
    )
    _ = try await loop.interrupt(id, with: packet)
    _ = try await loop.resume(id)
    let closed = try await loop.close(id)

    #expect(closed.state == .closed)
    #expect(try await repository.intention(id: id)?.state == .closed)
}
