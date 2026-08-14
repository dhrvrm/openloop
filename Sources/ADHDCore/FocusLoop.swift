import Foundation

public enum FocusLoopError: Error, Equatable {
    case intentionNotFound(UUID)
    case focusSessionNotFound(UUID)
    case currentFocusExists(UUID)
}

public struct FocusUpdate: Equatable, Sendable {
    public let intention: Intention
    public let session: FocusSession

    public init(intention: Intention, session: FocusSession) {
        self.intention = intention
        self.session = session
    }
}

public actor FocusLoop {
    private let repository: any ThoughtRepository
    private let composer: InterruptionSnapshotComposer

    public init(
        repository: any ThoughtRepository,
        composer: InterruptionSnapshotComposer = InterruptionSnapshotComposer()
    ) {
        self.repository = repository
        self.composer = composer
    }

    public func start(_ intentionID: UUID, at date: Date) async throws -> FocusUpdate {
        var intention = try await loadIntention(intentionID)
        if let current = try await currentSession() {
            throw FocusLoopError.currentFocusExists(current.intentionID)
        }
        if intention.state != .active {
            try intention.transition(to: .active)
        }
        let session = FocusSession(intentionID: intentionID, startedAt: date)
        return try await persist(intention, session)
    }

    public func pause(_ intentionID: UUID, at date: Date) async throws -> FocusUpdate {
        let intention = try await loadIntention(intentionID)
        var session = try await loadSession(intentionID)
        try session.pause(at: date)
        return try await persist(intention, session)
    }

    public func continueSession(_ intentionID: UUID, at date: Date) async throws -> FocusUpdate {
        let intention = try await loadIntention(intentionID)
        var session = try await loadSession(intentionID)
        try session.continueSession(at: date)
        return try await persist(intention, session)
    }

    public func interrupt(
        _ intentionID: UUID,
        draft: InterruptionDraft,
        at date: Date
    ) async throws -> FocusUpdate {
        var intention = try await loadIntention(intentionID)
        var session = try await loadSession(intentionID)
        let packet = try await composer.compose(draft, at: date)
        try intention.interrupt(with: packet)
        try session.interrupt(at: date)
        return try await persist(intention, session)
    }

    public func resume(_ intentionID: UUID, at date: Date) async throws -> FocusUpdate {
        if let current = try await currentSession() {
            throw FocusLoopError.currentFocusExists(current.intentionID)
        }
        var intention = try await loadIntention(intentionID)
        var session = try await existingSession(intentionID) ?? FocusSession(
            intentionID: intentionID,
            startedAt: date,
            state: .interrupted
        )
        try intention.resume()
        try session.resume(at: date)
        return try await persist(intention, session)
    }

    public func finish(_ intentionID: UUID, at date: Date) async throws -> FocusUpdate {
        var intention = try await loadIntention(intentionID)
        var session = try await loadSession(intentionID)
        try intention.transition(to: .closed)
        try session.finish(at: date)
        return try await persist(intention, session)
    }

    private func persist(
        _ intention: Intention,
        _ session: FocusSession
    ) async throws -> FocusUpdate {
        try await repository.save(intention: intention, focusSession: session)
        return FocusUpdate(intention: intention, session: session)
    }

    private func loadIntention(_ id: UUID) async throws -> Intention {
        guard let intention = try await repository.intention(id: id) else {
            throw FocusLoopError.intentionNotFound(id)
        }
        return intention
    }

    private func loadSession(_ intentionID: UUID) async throws -> FocusSession {
        guard let session = try await existingSession(intentionID) else {
            throw FocusLoopError.focusSessionNotFound(intentionID)
        }
        return session
    }

    private func existingSession(_ intentionID: UUID) async throws -> FocusSession? {
        try await repository.focusSessions()
            .filter({ $0.intentionID == intentionID && $0.state != .finished })
            .sorted(by: Self.newerSession)
            .first
    }

    private func currentSession() async throws -> FocusSession? {
        try await repository.focusSessions().first {
            $0.state == .active || $0.state == .paused
        }
    }

    private static func newerSession(_ lhs: FocusSession, _ rhs: FocusSession) -> Bool {
        if lhs.startedAt == rhs.startedAt { return lhs.id.uuidString > rhs.id.uuidString }
        return lhs.startedAt > rhs.startedAt
    }
}
