import Foundation

public struct InterruptionDraft: Equatable, Sendable {
    public let justCompleted: String?
    public let nextAction: String
    public let blocker: String?
    public let references: [String]

    public init(
        justCompleted: String?,
        nextAction: String,
        blocker: String?,
        references: [String]
    ) {
        self.justCompleted = justCompleted
        self.nextAction = nextAction
        self.blocker = blocker
        self.references = references
    }
}

public protocol ContextReferenceProvider: Sendable {
    func references() async throws -> [String]
}

public struct CompositeContextReferenceProvider: ContextReferenceProvider, Sendable {
    private let providers: [any ContextReferenceProvider]

    public init(_ providers: [any ContextReferenceProvider]) {
        self.providers = providers
    }

    public func references() async throws -> [String] {
        var result: [String] = []
        for provider in providers {
            result.append(contentsOf: (try? await provider.references()) ?? [])
        }
        return result
    }
}

public struct InterruptionSnapshotComposer: Sendable {
    private let contextProvider: (any ContextReferenceProvider)?

    public init(contextProvider: (any ContextReferenceProvider)? = nil) {
        self.contextProvider = contextProvider
    }

    public func compose(_ draft: InterruptionDraft, at date: Date) async throws -> ReturnPacket {
        let contextualReferences = (try? await contextProvider?.references()) ?? []
        return try ReturnPacket(
            capturedAt: date,
            justCompleted: Self.optionalText(draft.justCompleted),
            nextAction: draft.nextAction,
            blocker: Self.optionalText(draft.blocker),
            references: Self.normalizedReferences(draft.references + contextualReferences)
        )
    }

    private static func optionalText(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedReferences(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized.isEmpty == false, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }
}
