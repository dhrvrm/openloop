import Foundation
import Testing
@testable import ADHDCore

private actor V1LifecycleRepository: ThoughtRepository {
    var intentions: [UUID: Intention] = [:]
    var sessions: [UUID: FocusSession] = [:]

    func save(capture: RawCapture) async throws {}
    func save(proposal: ClarificationProposal) async throws {}
    func save(intention: Intention) async throws { intentions[intention.id] = intention }
    func save(intentions values: [Intention]) async throws {
        for value in values { intentions[value.id] = value }
    }
    func save(intention: Intention, focusSession: FocusSession) async throws {
        intentions[intention.id] = intention
        sessions[focusSession.id] = focusSession
    }
    func proposal(captureID: UUID) async throws -> ClarificationProposal? { nil }
    func captures(disposition: Disposition) async throws -> [RawCapture] { [] }
    func intention(id: UUID) async throws -> Intention? { intentions[id] }
    func openIntentions() async throws -> [Intention] {
        intentions.values.filter { $0.state != .closed && $0.state != .released }
    }
    func focusSessions() async throws -> [FocusSession] { Array(sessions.values) }
}

private struct V1UnusedClarifier: ClarificationProvider {
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

@Suite("v1 lifecycle")
struct V1LifecycleTests {
    @Test func manualOrderControlsTheReadyQueueAndPersistsAsOneBatch() async throws {
        let repository = V1LifecycleRepository()
        let values = (0..<3).map { index in
            let id = UUID()
            return Intention(
                id: id,
                sourceCaptureID: id,
                desiredOutcome: "Outcome \(index)",
                nextAction: "Action \(index)",
                state: .open,
                createdAt: Date(timeIntervalSince1970: Double(index)),
                returnPacket: nil
            )
        }
        for value in values { try await repository.save(intention: value) }
        let loop = ThoughtLoop(repository: repository, clarifier: V1UnusedClarifier())

        try await loop.reorderOpenIntentions([values[2].id, values[0].id, values[1].id])

        let items = try await ThoughtReadModels(repository: repository).openLoops()
        #expect(items.map(\.id) == [values[2].id, values[0].id, values[1].id])
    }

    @Test func releaseEndsTheCurrentFocusSessionAtomically() async throws {
        let repository = V1LifecycleRepository()
        let id = UUID()
        let intention = Intention(
            id: id,
            sourceCaptureID: id,
            desiredOutcome: "Remove an obligation",
            nextAction: "Begin",
            state: .open,
            createdAt: Date(timeIntervalSince1970: 1),
            returnPacket: nil
        )
        try await repository.save(intention: intention)
        let focus = FocusLoop(repository: repository)
        _ = try await focus.start(id, at: Date(timeIntervalSince1970: 2))

        let update = try await focus.release(id, at: Date(timeIntervalSince1970: 5))

        #expect(update.intention.state == .released)
        #expect(update.session.state == .finished)
        #expect(try await repository.intention(id: id)?.state == .released)
    }

    @Test func destinationMovePersistsAndItsInverseRestoresTheSource() async throws {
        let repository = V1LifecycleRepository()
        let id = UUID()
        try await repository.save(intention: Intention(
            id: id,
            sourceCaptureID: id,
            desiredOutcome: "Plan later work",
            nextAction: "Review scope",
            state: .open,
            createdAt: .now,
            returnPacket: nil,
            manualOrder: 3
        ))
        let loop = ThoughtLoop(repository: repository, clarifier: V1UnusedClarifier())

        let move = try await loop.moveIntention(id, to: .someday)
        #expect(try await repository.intention(id: id)?.destination == .someday)

        try await loop.apply(move.inverse)
        #expect(try await repository.intention(id: id)?.destination == .anytime)
        #expect(try await repository.intention(id: id)?.manualOrder == 3)
    }
}
