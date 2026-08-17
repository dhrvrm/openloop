import Foundation

public enum ContextCollectionMode: String, Codable, Equatable, Hashable, Sendable {
    case privateMode
    case focusTrail
}

public enum ContextTrailError: Error, Equatable, Sendable {
    case invalidEvaluationInput
}

public struct ContextTrailSettings: Codable, Equatable, Sendable {
    public static let maximumRetentionHours = 8
    public static let maximumEventsPerSession = 100

    public let mode: ContextCollectionMode
    public let retentionHours: Int

    public init(mode: ContextCollectionMode = .privateMode, retentionHours: Int = 8) {
        self.mode = mode
        self.retentionHours = min(Self.maximumRetentionHours, max(1, retentionHours))
    }

    public var isEnabled: Bool { mode == .focusTrail }
}

public struct ContextTrailEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let intentionID: UUID
    public let focusSessionID: UUID
    public let observedAt: Date
    public let application: ApplicationContext

    public init(
        id: UUID = UUID(),
        intentionID: UUID,
        focusSessionID: UUID,
        observedAt: Date,
        application: ApplicationContext
    ) {
        self.id = id
        self.intentionID = intentionID
        self.focusSessionID = focusSessionID
        self.observedAt = observedAt
        self.application = application
    }
}

public struct ContextEpisode: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let focusSessionID: UUID
    public let application: ApplicationContext
    public let startedAt: Date
    public let lastObservedAt: Date
    public let observationCount: Int

    public init(
        id: UUID,
        focusSessionID: UUID,
        application: ApplicationContext,
        startedAt: Date,
        lastObservedAt: Date,
        observationCount: Int
    ) {
        self.id = id
        self.focusSessionID = focusSessionID
        self.application = application
        self.startedAt = startedAt
        self.lastObservedAt = lastObservedAt
        self.observationCount = max(1, observationCount)
    }
}

public protocol ContextTrailProviding: Sendable {
    func settings() async throws -> ContextTrailSettings
    func setEnabled(_ enabled: Bool) async throws -> ContextTrailSettings
    func observe(_ application: ApplicationContext, at date: Date) async throws -> ContextTrailEvent?
    func currentEpisodes(at date: Date) async throws -> [ContextEpisode]
}

public enum ContextTrailPolicy {
    public static func boundedEvents(
        _ events: [ContextTrailEvent],
        focusSessionID: UUID,
        through date: Date,
        retentionHours: Int
    ) -> [ContextTrailEvent] {
        let hours = min(ContextTrailSettings.maximumRetentionHours, max(1, retentionHours))
        let cutoff = date.addingTimeInterval(-Double(hours) * 3_600)
        let ordered = events
            .filter {
                $0.focusSessionID == focusSessionID
                    && $0.observedAt >= cutoff
                    && $0.observedAt <= date
            }
            .sorted(by: eventComesBefore)
        return Array(ordered.suffix(ContextTrailSettings.maximumEventsPerSession))
    }

    public static func episodes(
        from events: [ContextTrailEvent],
        focusSessionID: UUID,
        through date: Date,
        retentionHours: Int
    ) -> [ContextEpisode] {
        boundedEvents(
            events,
            focusSessionID: focusSessionID,
            through: date,
            retentionHours: retentionHours
        ).reduce(into: [ContextEpisode]()) { episodes, event in
            if let last = episodes.last,
               last.application.bundleIdentifier == event.application.bundleIdentifier {
                episodes[episodes.count - 1] = ContextEpisode(
                    id: last.id,
                    focusSessionID: last.focusSessionID,
                    application: last.application,
                    startedAt: last.startedAt,
                    lastObservedAt: event.observedAt,
                    observationCount: last.observationCount + 1
                )
            } else {
                episodes.append(ContextEpisode(
                    id: event.id,
                    focusSessionID: event.focusSessionID,
                    application: event.application,
                    startedAt: event.observedAt,
                    lastObservedAt: event.observedAt,
                    observationCount: 1
                ))
            }
        }
    }

    public static func eventComesBefore(_ lhs: ContextTrailEvent, _ rhs: ContextTrailEvent) -> Bool {
        if lhs.observedAt != rhs.observedAt { return lhs.observedAt < rhs.observedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
