import Foundation

public struct NowItem: Equatable, Sendable {
    public let intentionID: UUID
    public let desiredOutcome: String
    public let nextAction: String
    public let state: IntentionState
}

public struct LaterItem: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let text: String
    public let disposition: Disposition
}

public struct ThoughtReadModels: Sendable {
    private let repository: any ThoughtRepository

    public init(repository: any ThoughtRepository) {
        self.repository = repository
    }

    public func now() async throws -> NowItem? {
        let intentions = try await repository.openIntentions()
        return intentions.sorted(by: comesBefore).first.map {
            NowItem(
                intentionID: $0.id,
                desiredOutcome: $0.desiredOutcome,
                nextAction: $0.nextAction,
                state: $0.state
            )
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

    private func comesBefore(_ lhs: Intention, _ rhs: Intention) -> Bool {
        let rank: [IntentionState: Int] = [.active: 0, .interrupted: 1, .open: 2]
        let left = rank[lhs.state] ?? 3
        let right = rank[rhs.state] ?? 3
        if left != right { return left < right }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
