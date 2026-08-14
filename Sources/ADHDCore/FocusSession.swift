import Foundation

public enum FocusSessionState: String, Codable, Equatable, Hashable, Sendable {
    case active
    case paused
    case interrupted
    case finished
}

public enum FocusSessionError: Error, Equatable {
    case invalidTransition(from: FocusSessionState, to: FocusSessionState)
}

public struct FocusSession: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let intentionID: UUID
    public let startedAt: Date
    public private(set) var state: FocusSessionState
    public private(set) var accumulatedSeconds: TimeInterval
    public private(set) var activeSince: Date?

    public init(
        id: UUID = UUID(),
        intentionID: UUID,
        startedAt: Date,
        state: FocusSessionState = .active,
        accumulatedSeconds: TimeInterval = 0,
        activeSince: Date? = nil
    ) {
        self.id = id
        self.intentionID = intentionID
        self.startedAt = startedAt
        self.state = state
        self.accumulatedSeconds = max(0, accumulatedSeconds)
        self.activeSince = activeSince ?? (state == .active ? startedAt : nil)
    }

    public func elapsed(at date: Date) -> TimeInterval {
        guard state == .active, let activeSince else { return accumulatedSeconds }
        return accumulatedSeconds + max(0, date.timeIntervalSince(activeSince))
    }

    public mutating func pause(at date: Date) throws {
        guard state == .active else {
            throw FocusSessionError.invalidTransition(from: state, to: .paused)
        }
        accrueActiveTime(until: date)
        state = .paused
        activeSince = nil
    }

    public mutating func continueSession(at date: Date) throws {
        guard state == .paused else {
            throw FocusSessionError.invalidTransition(from: state, to: .active)
        }
        state = .active
        activeSince = date
    }

    public mutating func interrupt(at date: Date) throws {
        guard state == .active || state == .paused else {
            throw FocusSessionError.invalidTransition(from: state, to: .interrupted)
        }
        if state == .active { accrueActiveTime(until: date) }
        state = .interrupted
        activeSince = nil
    }

    public mutating func resume(at date: Date) throws {
        guard state == .interrupted else {
            throw FocusSessionError.invalidTransition(from: state, to: .active)
        }
        state = .active
        activeSince = date
    }

    public mutating func finish(at date: Date) throws {
        guard state != .finished else {
            throw FocusSessionError.invalidTransition(from: state, to: .finished)
        }
        if state == .active { accrueActiveTime(until: date) }
        state = .finished
        activeSince = nil
    }

    private mutating func accrueActiveTime(until date: Date) {
        guard let activeSince else { return }
        accumulatedSeconds += max(0, date.timeIntervalSince(activeSince))
    }
}
