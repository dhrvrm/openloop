import Foundation

public enum ThoughtLoopError: Error, Equatable {
    case intentionNotFound(UUID)
    case captureNotFound(UUID)
    case intentionCannotBeReviewed(UUID, IntentionState)
    case invalidIntentionOrder
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
        guard let captures = try? await repository.capturesRequiringClarification() else { return 0 }
        var recovered = 0
        for capture in captures {
            if (try? await clarify(capture)) != nil { recovered += 1 }
        }
        return recovered
    }

    public func review(
        captureID: UUID,
        disposition: Disposition,
        desiredOutcome: String?,
        nextAction: String?,
        at date: Date
    ) async throws -> ClarificationCorrection {
        guard let capture = try await repository.capture(id: captureID) else {
            throw ThoughtLoopError.captureNotFound(captureID)
        }
        let previousProposal = try await repository.proposal(captureID: captureID)
        let proposal = try ClarificationProposal(
            captureID: captureID,
            disposition: disposition,
            desiredOutcome: desiredOutcome,
            nextAction: nextAction,
            confidence: 1
        )
        let currentIntention = try await repository.intention(id: captureID)
        let reviewedIntention: Intention?

        if var currentIntention {
            guard currentIntention.state == .open else {
                throw ThoughtLoopError.intentionCannotBeReviewed(
                    currentIntention.id,
                    currentIntention.state
                )
            }
            if disposition == .action,
               let outcome = proposal.desiredOutcome,
               let action = proposal.nextAction {
                reviewedIntention = Intention(
                    id: currentIntention.id,
                    sourceCaptureID: currentIntention.sourceCaptureID,
                    desiredOutcome: outcome,
                    nextAction: action,
                    state: .open,
                    createdAt: currentIntention.createdAt,
                    returnPacket: nil,
                    manualOrder: currentIntention.manualOrder,
                    destination: currentIntention.destination,
                    heading: currentIntention.heading,
                    scheduledAt: currentIntention.scheduledAt,
                    deadline: currentIntention.deadline,
                    tags: currentIntention.tags,
                    checklist: currentIntention.checklist
                )
            } else {
                try currentIntention.transition(to: .released)
                reviewedIntention = currentIntention
            }
        } else {
            reviewedIntention = makeIntention(from: proposal, capture: capture)
        }

        let correction = ClarificationCorrection(
            captureID: captureID,
            reviewedAt: date,
            previousProposal: previousProposal,
            proposal: proposal
        )
        try await repository.apply(
            clarificationCorrection: correction,
            intention: reviewedIntention
        )
        return correction
    }

    private func makeIntention(
        from proposal: ClarificationProposal,
        capture: RawCapture
    ) -> Intention? {
        if proposal.disposition == .action,
           let outcome = proposal.desiredOutcome,
           let nextAction = proposal.nextAction {
            let value = Intention(
                id: capture.id,
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

    public func release(_ id: UUID) async throws -> Intention {
        var intention = try await loadIntention(id)
        try intention.transition(to: .released)
        try await repository.save(intention: intention)
        return intention
    }

    public func reorderOpenIntentions(_ orderedIDs: [UUID]) async throws {
        let intentions = try await repository.openIntentions()
        let byID = Dictionary(uniqueKeysWithValues: intentions.map { ($0.id, $0) })
        let knownIDs = Set(byID.keys)
        guard orderedIDs.count == knownIDs.count, Set(orderedIDs) == knownIDs else {
            throw ThoughtLoopError.invalidIntentionOrder
        }
        let reordered = orderedIDs.enumerated().map { index, id in
            var intention = byID[id]!
            intention.place(at: index)
            return intention
        }
        try await repository.save(intentions: reordered)
    }

    @discardableResult
    public func moveIntention(
        _ id: UUID,
        to destination: IntentionDestination
    ) async throws -> IntentionMove {
        var intention = try await loadIntention(id)
        let move = IntentionMove(
            intentionID: id,
            source: intention.destination,
            destination: destination,
            sourceOrder: intention.manualOrder
        )
        intention.move(to: destination)
        try await repository.save(intention: intention)
        return move
    }

    public func apply(_ move: IntentionMove) async throws {
        var intention = try await loadIntention(move.intentionID)
        intention.move(to: move.destination, order: move.sourceOrder)
        try await repository.save(intention: intention)
    }

    private func loadIntention(_ id: UUID) async throws -> Intention {
        guard let intention = try await repository.intention(id: id) else {
            throw ThoughtLoopError.intentionNotFound(id)
        }
        return intention
    }
}
