import Foundation

public enum IntentionState: String, Codable, Equatable, Hashable, Sendable {
    case open
    case active
    case interrupted
    case closed
    case released
}

public enum IntentionDestination: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case anytime
    case upcoming
    case someday
}

public struct IntentionChecklistItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var text: String
    public var isCompleted: Bool

    public init(id: UUID = UUID(), text: String, isCompleted: Bool = false) {
        self.id = id
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isCompleted = isCompleted
    }
}

public struct IntentionMove: Equatable, Sendable {
    public let intentionID: UUID
    public let source: IntentionDestination
    public let destination: IntentionDestination
    public let sourceOrder: Int?

    public init(
        intentionID: UUID,
        source: IntentionDestination,
        destination: IntentionDestination,
        sourceOrder: Int?
    ) {
        self.intentionID = intentionID
        self.source = source
        self.destination = destination
        self.sourceOrder = sourceOrder
    }

    public var inverse: IntentionMove {
        IntentionMove(
            intentionID: intentionID,
            source: destination,
            destination: source,
            sourceOrder: sourceOrder
        )
    }
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
    public private(set) var destination: IntentionDestination
    public private(set) var heading: String?
    public private(set) var scheduledAt: Date?
    public private(set) var deadline: Date?
    public private(set) var tags: [String]
    public private(set) var checklist: [IntentionChecklistItem]

    public init(
        id: UUID,
        sourceCaptureID: UUID,
        desiredOutcome: String,
        nextAction: String,
        state: IntentionState,
        createdAt: Date,
        returnPacket: ReturnPacket?,
        manualOrder: Int? = nil,
        destination: IntentionDestination = .anytime,
        heading: String? = nil,
        scheduledAt: Date? = nil,
        deadline: Date? = nil,
        tags: [String] = [],
        checklist: [IntentionChecklistItem] = []
    ) {
        self.id = id
        self.sourceCaptureID = sourceCaptureID
        self.desiredOutcome = desiredOutcome
        self.nextAction = nextAction
        self.state = state
        self.createdAt = createdAt
        self.returnPacket = returnPacket
        self.manualOrder = manualOrder
        self.destination = destination
        self.heading = heading?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.scheduledAt = scheduledAt
        self.deadline = deadline
        self.tags = Self.normalizedTags(tags)
        self.checklist = checklist.filter { !$0.text.isEmpty }
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

    public mutating func move(to destination: IntentionDestination, order: Int? = nil) {
        self.destination = destination
        if let order { manualOrder = max(0, order) }
    }

    public mutating func organize(
        heading: String?,
        scheduledAt: Date?,
        deadline: Date?,
        tags: [String],
        checklist: [IntentionChecklistItem]
    ) {
        self.heading = heading?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.scheduledAt = scheduledAt
        self.deadline = deadline
        self.tags = Self.normalizedTags(tags)
        self.checklist = checklist.filter { !$0.text.isEmpty }
    }

    private static func normalizedTags(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return nil }
            let key = normalized.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return normalized
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, sourceCaptureID, desiredOutcome, nextAction, state, createdAt
        case returnPacket, manualOrder, destination, heading, scheduledAt, deadline, tags, checklist
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            sourceCaptureID: try container.decode(UUID.self, forKey: .sourceCaptureID),
            desiredOutcome: try container.decode(String.self, forKey: .desiredOutcome),
            nextAction: try container.decode(String.self, forKey: .nextAction),
            state: try container.decode(IntentionState.self, forKey: .state),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            returnPacket: try container.decodeIfPresent(ReturnPacket.self, forKey: .returnPacket),
            manualOrder: try container.decodeIfPresent(Int.self, forKey: .manualOrder),
            destination: try container.decodeIfPresent(IntentionDestination.self, forKey: .destination)
                ?? .anytime,
            heading: try container.decodeIfPresent(String.self, forKey: .heading),
            scheduledAt: try container.decodeIfPresent(Date.self, forKey: .scheduledAt),
            deadline: try container.decodeIfPresent(Date.self, forKey: .deadline),
            tags: try container.decodeIfPresent([String].self, forKey: .tags) ?? [],
            checklist: try container.decodeIfPresent(
                [IntentionChecklistItem].self,
                forKey: .checklist
            ) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sourceCaptureID, forKey: .sourceCaptureID)
        try container.encode(desiredOutcome, forKey: .desiredOutcome)
        try container.encode(nextAction, forKey: .nextAction)
        try container.encode(state, forKey: .state)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(returnPacket, forKey: .returnPacket)
        try container.encodeIfPresent(manualOrder, forKey: .manualOrder)
        try container.encode(destination, forKey: .destination)
        try container.encodeIfPresent(heading, forKey: .heading)
        try container.encodeIfPresent(scheduledAt, forKey: .scheduledAt)
        try container.encodeIfPresent(deadline, forKey: .deadline)
        try container.encode(tags, forKey: .tags)
        try container.encode(checklist, forKey: .checklist)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
