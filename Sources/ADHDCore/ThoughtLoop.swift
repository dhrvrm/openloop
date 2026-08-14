import Foundation

public enum ThoughtLoopError: Error, Equatable {
    case intentionNotFound(UUID)
}

public struct CaptureResult: Sendable {
    public let capture: RawCapture
    public let proposal: ClarificationProposal
    public let intention: Intention?
}

public struct ThoughtLoop: Sendable {
    private let repository: any ThoughtRepository
    private let clarifier: any ClarificationProvider

    public init(
        repository: any ThoughtRepository,
        clarifier: any ClarificationProvider
    ) {
        self.repository = repository
        self.clarifier = clarifier
    }

    public func capture(text: String, at date: Date) async throws -> CaptureResult {
        let capture = try await accept(text: text, at: date)
        return try await clarify(capture)
    }

    public func accept(text: String, at date: Date) async throws -> RawCapture {
        let capture = try RawCapture(createdAt: date, text: text)
        try await repository.save(capture: capture)
        return capture
    }

    public func clarify(_ capture: RawCapture) async throws -> CaptureResult {
        let proposal = try await clarifier.propose(for: capture)
        let intention = makeIntention(from: proposal, capture: capture)
        try await repository.save(proposal: proposal, intention: intention)

        return CaptureResult(capture: capture, proposal: proposal, intention: intention)
    }

    public func recoverUnclarifiedCaptures() async -> Int {
        guard let captures = try? await repository.unclarifiedCaptures() else { return 0 }
        var recovered = 0
        for capture in captures {
            if (try? await clarify(capture)) != nil { recovered += 1 }
        }
        return recovered
    }

    private func makeIntention(
        from proposal: ClarificationProposal,
        capture: RawCapture
    ) -> Intention? {
        if proposal.disposition == .action,
           let outcome = proposal.desiredOutcome,
           let nextAction = proposal.nextAction {
            let value = Intention(
                id: UUID(),
                sourceCaptureID: capture.id,
                desiredOutcome: outcome,
                nextAction: nextAction,
                state: .open,
                createdAt: capture.createdAt,
                returnPacket: nil
            )
            return value
        }
        return nil
    }

    public func start(_ id: UUID) async throws -> Intention {
        var intention = try await loadIntention(id)
        try intention.transition(to: .active)
        try await repository.save(intention: intention)
        return intention
    }

    public func interrupt(_ id: UUID, with packet: ReturnPacket) async throws -> Intention {
        var intention = try await loadIntention(id)
        try intention.interrupt(with: packet)
        try await repository.save(intention: intention)
        return intention
    }

    public func resume(_ id: UUID) async throws -> Intention {
        var intention = try await loadIntention(id)
        try intention.resume()
        try await repository.save(intention: intention)
        return intention
    }

    public func close(_ id: UUID) async throws -> Intention {
        var intention = try await loadIntention(id)
        try intention.transition(to: .closed)
        try await repository.save(intention: intention)
        return intention
    }

    private func loadIntention(_ id: UUID) async throws -> Intention {
        guard let intention = try await repository.intention(id: id) else {
            throw ThoughtLoopError.intentionNotFound(id)
        }
        return intention
    }
}
