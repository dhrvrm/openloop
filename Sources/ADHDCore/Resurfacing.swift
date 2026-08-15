import Foundation

public enum ResurfacingValueError: Error, Equatable {
    case emptyBundleIdentifier
    case emptyApplicationName
}

public struct ApplicationContext: Codable, Equatable, Hashable, Sendable {
    public let bundleIdentifier: String
    public let applicationName: String

    public init(bundleIdentifier: String, applicationName: String) throws {
        let normalizedIdentifier = bundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedName = applicationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedIdentifier.isEmpty == false else {
            throw ResurfacingValueError.emptyBundleIdentifier
        }
        guard normalizedName.isEmpty == false else {
            throw ResurfacingValueError.emptyApplicationName
        }
        self.bundleIdentifier = normalizedIdentifier
        self.applicationName = normalizedName
    }
}

public struct ContextEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let observedAt: Date
    public let application: ApplicationContext

    public init(
        id: UUID = UUID(),
        observedAt: Date,
        application: ApplicationContext
    ) {
        self.id = id
        self.observedAt = observedAt
        self.application = application
    }
}

public struct ResurfacingRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID { intentionID }
    public let intentionID: UUID
    public let application: ApplicationContext
    public let createdAt: Date

    public init(
        intentionID: UUID,
        application: ApplicationContext,
        createdAt: Date
    ) {
        self.intentionID = intentionID
        self.application = application
        self.createdAt = createdAt
    }
}

public enum SuggestionEventKind: String, Codable, Equatable, Sendable {
    case shown
    case started
    case later
    case never
}

public struct SuggestionEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let intentionID: UUID
    public let occurredAt: Date
    public let application: ApplicationContext
    public let kind: SuggestionEventKind

    public init(
        id: UUID = UUID(),
        intentionID: UUID,
        occurredAt: Date,
        application: ApplicationContext,
        kind: SuggestionEventKind
    ) {
        self.id = id
        self.intentionID = intentionID
        self.occurredAt = occurredAt
        self.application = application
        self.kind = kind
    }
}

public struct RelevanceContribution: Codable, Equatable, Identifiable, Sendable {
    public var id: String { label }
    public let label: String
    public let value: Double
    public let explanation: String

    public init(label: String, value: Double, explanation: String) {
        self.label = label
        self.value = value
        self.explanation = explanation
    }
}

public struct ContextualSuggestion: Equatable, Identifiable, Sendable {
    public var id: UUID { intentionID }
    public let intentionID: UUID
    public let desiredOutcome: String
    public let nextAction: String
    public let score: Double
    public let contributions: [RelevanceContribution]

    public var why: String {
        contributions.map(\.explanation).joined(separator: ", ")
    }
}

public struct RelevanceScorer: Sendable {
    public static let threshold = 1.0
    public static let maximumSuggestions = 2

    public init() {}

    public func suggestions(
        intentions: [Intention],
        rules: [ResurfacingRule],
        context: ContextEvent
    ) -> [ContextualSuggestion] {
        let intentionsByID = Dictionary(uniqueKeysWithValues: intentions.map { ($0.id, $0) })
        return rules.compactMap { rule -> (ContextualSuggestion, Date)? in
            guard rule.application.bundleIdentifier == context.application.bundleIdentifier,
                  let intention = intentionsByID[rule.intentionID],
                  intention.state == .open else {
                return nil
            }
            let contribution = RelevanceContribution(
                label: "Application match",
                value: 1,
                explanation: "Linked to \(context.application.applicationName)"
            )
            let score = contribution.value
            guard score >= Self.threshold else { return nil }
            return (
                ContextualSuggestion(
                    intentionID: intention.id,
                    desiredOutcome: intention.desiredOutcome,
                    nextAction: intention.nextAction,
                    score: score,
                    contributions: [contribution]
                ),
                intention.createdAt
            )
        }.sorted {
            if $0.0.score != $1.0.score { return $0.0.score > $1.0.score }
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            return $0.0.intentionID.uuidString < $1.0.intentionID.uuidString
        }.prefix(Self.maximumSuggestions).map(\.0)
    }
}

public struct ResurfacingPolicy: Sendable {
    public static let shownCooldown: TimeInterval = 4 * 60 * 60
    public static let laterSuppression: TimeInterval = 24 * 60 * 60

    public init() {}

    public func isEligible(
        rule: ResurfacingRule,
        events: [SuggestionEvent],
        at date: Date
    ) -> Bool {
        let relevant = events.filter {
            $0.intentionID == rule.intentionID && $0.occurredAt >= rule.createdAt
        }
        if relevant.contains(where: { $0.kind == .never }) { return false }
        if let latestLater = relevant
            .filter({ $0.kind == .later })
            .map(\.occurredAt)
            .max(),
           date < latestLater.addingTimeInterval(Self.laterSuppression) {
            return false
        }
        if let latestShown = relevant
            .filter({ $0.kind == .shown })
            .map(\.occurredAt)
            .max(),
           date < latestShown.addingTimeInterval(Self.shownCooldown) {
            return false
        }
        return true
    }
}

public enum ResurfacingFeedback: Equatable, Sendable {
    case started
    case later
    case never

    fileprivate var eventKind: SuggestionEventKind {
        switch self {
        case .started: .started
        case .later: .later
        case .never: .never
        }
    }
}

public enum ResurfacingLoopError: Error, Equatable {
    case intentionNotFound
    case intentionNotOpen
    case ruleNotFound
}

public struct ResurfacingLoop: Sendable {
    private let repository: any ThoughtRepository
    private let scorer: RelevanceScorer
    private let policy: ResurfacingPolicy

    public init(
        repository: any ThoughtRepository,
        scorer: RelevanceScorer = RelevanceScorer(),
        policy: ResurfacingPolicy = ResurfacingPolicy()
    ) {
        self.repository = repository
        self.scorer = scorer
        self.policy = policy
    }

    public func suggest(
        for context: ContextEvent,
        at date: Date
    ) async throws -> [ContextualSuggestion] {
        async let intentionsValue = repository.openIntentions()
        async let rulesValue = repository.resurfacingRules()
        async let eventsValue = repository.suggestionEvents()
        let (intentions, rules, events) = try await (
            intentionsValue,
            rulesValue,
            eventsValue
        )
        let eligibleRules = rules.filter {
            policy.isEligible(rule: $0, events: events, at: date)
        }
        let suggestions = scorer.suggestions(
            intentions: intentions,
            rules: eligibleRules,
            context: context
        )
        for suggestion in suggestions {
            try await repository.append(suggestionEvent: SuggestionEvent(
                intentionID: suggestion.intentionID,
                occurredAt: date,
                application: context.application,
                kind: .shown
            ))
        }
        return suggestions
    }

    @discardableResult
    public func recordFeedback(
        _ feedback: ResurfacingFeedback,
        intentionID: UUID,
        application: ApplicationContext,
        at date: Date
    ) async throws -> SuggestionEvent {
        guard let intention = try await repository.intention(id: intentionID) else {
            throw ResurfacingLoopError.intentionNotFound
        }
        guard intention.state == .open else {
            throw ResurfacingLoopError.intentionNotOpen
        }
        guard try await repository.resurfacingRules().contains(where: {
            $0.intentionID == intentionID
        }) else {
            throw ResurfacingLoopError.ruleNotFound
        }
        let event = SuggestionEvent(
            intentionID: intentionID,
            occurredAt: date,
            application: application,
            kind: feedback.eventKind
        )
        try await repository.append(suggestionEvent: event)
        return event
    }
}
