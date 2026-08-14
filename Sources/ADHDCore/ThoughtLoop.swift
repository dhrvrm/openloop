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
        try await repository.save(proposal: proposal)

        let intention = try await makeIntention(from: proposal, capture: capture)

        return CaptureResult(capture: capture, proposal: proposal, intention: intention)
    }

    private func makeIntention(
        from proposal: ClarificationProposal,
        capture: RawCapture
    ) async throws -> Intention? {
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
            try await repository.save(intention: value)
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
