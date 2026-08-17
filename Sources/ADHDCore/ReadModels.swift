import Foundation

public struct NowItem: Equatable, Sendable {
    public let intentionID: UUID
    public let desiredOutcome: String
    public let nextAction: String
    public let state: IntentionState
    public let focus: FocusNowItem?

    public func elapsed(at date: Date) -> TimeInterval {
        focus?.elapsed(at: date) ?? 0
    }
}

public struct FocusNowItem: Equatable, Sendable {
    public let sessionID: UUID
    public let state: FocusSessionState
    public let startedAt: Date
    public let accumulatedSeconds: TimeInterval
    public let activeSince: Date?

    public func elapsed(at date: Date) -> TimeInterval {
        guard state == .active, let activeSince else { return accumulatedSeconds }
        return accumulatedSeconds + max(0, date.timeIntervalSince(activeSince))
    }
}

public struct ReturnItem: Equatable, Identifiable, Sendable {
    public var id: UUID { intentionID }
    public let intentionID: UUID
    public let desiredOutcome: String
    public let justCompleted: String?
    public let nextAction: String
    public let blocker: String?
    public let references: [String]
    public let capturedAt: Date
}

public struct LaterItem: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let text: String
    public let disposition: Disposition
}

public struct ClarificationReviewItem: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let text: String
    public let disposition: Disposition
    public let desiredOutcome: String?
    public let nextAction: String?
    public let confidence: Double?
    public let intentionState: IntentionState?
    public let hasProposal: Bool

    public var needsDecision: Bool {
        hasProposal == false || disposition == .unclear
    }

    public var isEditable: Bool {
        intentionState == nil || intentionState == .open
    }
}

public struct OpenLoopItem: Equatable, Identifiable, Sendable {
    public var id: UUID { intentionID }
    public let intentionID: UUID
    public let sourceCaptureID: UUID
    public let desiredOutcome: String
    public let nextAction: String
    public let state: IntentionState
    public let createdAt: Date
}

public struct ThoughtReadModels: Sendable {
    private let repository: any ThoughtRepository

    public init(repository: any ThoughtRepository) {
        self.repository = repository
    }

    public func now() async throws -> NowItem? {
        let intentions = try await repository.openIntentions()
        let sessions = try await repository.focusSessions()
        if let currentSession = sessions
            .filter({ $0.state == .active || $0.state == .paused })
            .sorted(by: Self.focusComesBefore)
            .first,
           let intention = intentions.first(where: { $0.id == currentSession.intentionID }) {
            return makeNowItem(intention, focusSession: currentSession)
        }
        return intentions
            .filter { $0.state != .interrupted }
            .sorted(by: comesBefore)
            .first
            .map { makeNowItem($0, focusSession: nil) }
    }

    public func returns() async throws -> [ReturnItem] {
        try await repository.openIntentions().compactMap { intention in
            guard intention.state == .interrupted, let packet = intention.returnPacket else {
                return nil
            }
            return ReturnItem(
                intentionID: intention.id,
                desiredOutcome: intention.desiredOutcome,
                justCompleted: packet.justCompleted,
                nextAction: packet.nextAction,
                blocker: packet.blocker,
                references: packet.references,
                capturedAt: packet.capturedAt
            )
        }.sorted {
            if $0.capturedAt == $1.capturedAt {
                return $0.intentionID.uuidString < $1.intentionID.uuidString
            }
            return $0.capturedAt > $1.capturedAt
        }
    }

    public func later() async throws -> [LaterItem] {
        var items = try await repository.unclarifiedCaptures().map {
            LaterItem(id: $0.id, createdAt: $0.createdAt, text: $0.text, disposition: .unclear)
        }
        for disposition in [Disposition.later, .memory, .unclear] {
            for capture in try await repository.captures(disposition: disposition) {
                guard try await repository.proposal(captureID: capture.id) != nil else { continue }
                items.append(
                    LaterItem(
                        id: capture.id,
                        createdAt: capture.createdAt,
                        text: capture.text,
                        disposition: disposition
                    )
                )
            }
        }
        return items.sorted {
            if $0.createdAt == $1.createdAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.createdAt < $1.createdAt
        }
    }

    public func reviewQueue() async throws -> [ClarificationReviewItem] {
        let captures = try await repository.allCaptures()
        let intentions = try await repository.allIntentions()
        var items: [ClarificationReviewItem] = []
        for capture in captures {
            let proposal = try await repository.proposal(captureID: capture.id)
            guard proposal?.disposition != .release else { continue }
            let intention = intentions.first { $0.sourceCaptureID == capture.id }
            if proposal?.disposition == .action,
               intention?.state == .closed || intention?.state == .released {
                continue
            }
            items.append(
                ClarificationReviewItem(
                    id: capture.id,
                    createdAt: capture.createdAt,
                    text: capture.text,
                    disposition: proposal?.disposition ?? .unclear,
                    desiredOutcome: proposal?.desiredOutcome,
                    nextAction: proposal?.nextAction,
                    confidence: proposal?.confidence,
                    intentionState: intention?.state,
                    hasProposal: proposal != nil
                )
            )
        }
        return items.sorted {
            if $0.createdAt == $1.createdAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.createdAt > $1.createdAt
        }
    }

    public func openLoops() async throws -> [OpenLoopItem] {
        try await repository.openIntentions().map {
            OpenLoopItem(
                intentionID: $0.id,
                sourceCaptureID: $0.sourceCaptureID,
                desiredOutcome: $0.desiredOutcome,
                nextAction: $0.nextAction,
                state: $0.state,
                createdAt: $0.createdAt
            )
        }.sorted {
            let rank: [IntentionState: Int] = [.active: 0, .open: 1, .interrupted: 2]
            let left = rank[$0.state] ?? 3
            let right = rank[$1.state] ?? 3
            if left != right { return left < right }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.intentionID.uuidString < $1.intentionID.uuidString
        }
    }

    private func comesBefore(_ lhs: Intention, _ rhs: Intention) -> Bool {
        let rank: [IntentionState: Int] = [.active: 0, .open: 1]
        let left = rank[lhs.state] ?? 3
        let right = rank[rhs.state] ?? 3
        if left != right { return left < right }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func makeNowItem(
        _ intention: Intention,
        focusSession: FocusSession?
    ) -> NowItem {
        NowItem(
            intentionID: intention.id,
            desiredOutcome: intention.desiredOutcome,
            nextAction: intention.nextAction,
            state: intention.state,
            focus: focusSession.map {
                FocusNowItem(
                    sessionID: $0.id,
                    state: $0.state,
                    startedAt: $0.startedAt,
                    accumulatedSeconds: $0.accumulatedSeconds,
                    activeSince: $0.activeSince
                )
            }
        )
    }

    private static func focusComesBefore(_ lhs: FocusSession, _ rhs: FocusSession) -> Bool {
        if lhs.startedAt == rhs.startedAt { return lhs.id.uuidString < rhs.id.uuidString }
        return lhs.startedAt < rhs.startedAt
    }
}
