import Foundation

public enum IntentionState: String, Codable, Equatable, Hashable, Sendable {
    case open
    case active
    case interrupted
    case closed
    case released
}

public enum IntentionError: Error, Equatable {
    case emptyNextAction
    case invalidTransition(from: IntentionState, to: IntentionState)
    case interruptionRequiresActiveState
    case resumeRequiresInterruptedState
}

public struct ReturnPacket: Codable, Equatable, Sendable {
    public let capturedAt: Date
    public let justCompleted: String?
    public let nextAction: String
    public let blocker: String?
    public let references: [String]

    public init(
        capturedAt: Date,
        justCompleted: String?,
        nextAction: String,
        blocker: String?,
        references: [String]
    ) throws {
        let normalizedAction = nextAction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedAction.isEmpty == false else { throw IntentionError.emptyNextAction }

        self.capturedAt = capturedAt
        self.justCompleted = justCompleted
        self.nextAction = normalizedAction
        self.blocker = blocker
        self.references = references
    }
}

public struct Intention: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sourceCaptureID: UUID
    public let desiredOutcome: String
    public private(set) var nextAction: String
    public private(set) var state: IntentionState
    public let createdAt: Date
    public private(set) var returnPacket: ReturnPacket?
    public private(set) var manualOrder: Int?

    public init(
        id: UUID,
        sourceCaptureID: UUID,
        desiredOutcome: String,
        nextAction: String,
        state: IntentionState,
        createdAt: Date,
        returnPacket: ReturnPacket?,
        manualOrder: Int? = nil
    ) {
        self.id = id
        self.sourceCaptureID = sourceCaptureID
        self.desiredOutcome = desiredOutcome
        self.nextAction = nextAction
        self.state = state
        self.createdAt = createdAt
        self.returnPacket = returnPacket
        self.manualOrder = manualOrder
    }

    public mutating func transition(to target: IntentionState) throws {
        let allowed: Set<IntentionState>
        switch state {
        case .open:
            allowed = [.active, .closed, .released]
        case .active:
            allowed = [.interrupted, .closed, .released]
        case .interrupted:
            allowed = [.active, .closed, .released]
        case .closed, .released:
            allowed = []
        }

        guard allowed.contains(target) else {
            throw IntentionError.invalidTransition(from: state, to: target)
        }
        state = target
    }

    public mutating func interrupt(with packet: ReturnPacket) throws {
        guard state == .active else {
            throw IntentionError.interruptionRequiresActiveState
        }
        returnPacket = packet
        state = .interrupted
    }

    public mutating func resume() throws {
        guard state == .interrupted else {
            throw IntentionError.resumeRequiresInterruptedState
        }
        if let returnPacket {
            nextAction = returnPacket.nextAction
        }
        state = .active
    }

    public mutating func place(at index: Int) {
        manualOrder = max(0, index)
    }
}
