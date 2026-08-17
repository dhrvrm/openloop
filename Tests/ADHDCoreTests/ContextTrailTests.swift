import Foundation
import Testing
@testable import ADHDCore

@Test func contextTrailMergesOnlyConsecutiveMatchingApplications() throws {
    let sessionID = UUID()
    let intentionID = UUID()
    let xcode = try contextApplication("dev.xcode", "Xcode")
    let safari = try contextApplication("com.apple.safari", "Safari")
    let events = [
        contextEvent(1, application: xcode, intentionID: intentionID, sessionID: sessionID),
        contextEvent(2, application: xcode, intentionID: intentionID, sessionID: sessionID),
        contextEvent(3, application: safari, intentionID: intentionID, sessionID: sessionID),
        contextEvent(4, application: xcode, intentionID: intentionID, sessionID: sessionID),
    ]

    let episodes = ContextTrailPolicy.episodes(
        from: events,
        focusSessionID: sessionID,
        through: Date(timeIntervalSince1970: 10),
        retentionHours: 8
    )

    #expect(episodes.map(\.application.applicationName) == ["Xcode", "Safari", "Xcode"])
    #expect(episodes.map(\.observationCount) == [2, 1, 1])
    #expect(episodes[0].startedAt == Date(timeIntervalSince1970: 1))
    #expect(episodes[0].lastObservedAt == Date(timeIntervalSince1970: 2))
}

@Test func contextTrailDropsExpiredFutureAndOverflowObservations() throws {
    let sessionID = UUID()
    let intentionID = UUID()
    let app = try contextApplication("dev.editor", "Editor")
    let through = Date(timeIntervalSince1970: 40_000)
    var events = [contextEvent(
        -1,
        application: app,
        intentionID: intentionID,
        sessionID: sessionID,
        absoluteTime: through.addingTimeInterval(-3_601)
    )]
    events += try (0..<105).map { index in
        contextEvent(
            index,
            application: try contextApplication("dev.app.\(index)", "App \(index)"),
            intentionID: intentionID,
            sessionID: sessionID,
            absoluteTime: through.addingTimeInterval(Double(index - 105))
        )
    }
    events.append(contextEvent(
        999,
        application: app,
        intentionID: intentionID,
        sessionID: sessionID,
        absoluteTime: through.addingTimeInterval(1)
    ))

    let bounded = ContextTrailPolicy.boundedEvents(
        events,
        focusSessionID: sessionID,
        through: through,
        retentionHours: 1
    )

    #expect(bounded.count == 100)
    #expect(bounded.first?.application.applicationName == "App 5")
    #expect(bounded.last?.application.applicationName == "App 104")
}

@Test func contextTrailSettingsClampRetentionAndApplicationIdentityStaysValidated() throws {
    #expect(ContextTrailSettings(mode: .privateMode, retentionHours: -2).retentionHours == 1)
    #expect(ContextTrailSettings(mode: .focusTrail, retentionHours: 99).retentionHours == 8)
    #expect(throws: ResurfacingValueError.emptyBundleIdentifier) {
        _ = try ApplicationContext(bundleIdentifier: " ", applicationName: "Editor")
    }
    #expect(throws: ResurfacingValueError.emptyApplicationName) {
        _ = try ApplicationContext(bundleIdentifier: "dev.editor", applicationName: " ")
    }
}

@Test func contextTrailRecordsOnlyEnabledActiveFocusAndDeduplicatesConsecutiveApps() async throws {
    let repository = ContextTrailRepository()
    let session = FocusSession(
        id: UUID(),
        intentionID: UUID(),
        startedAt: Date(timeIntervalSince1970: 1)
    )
    await repository.seed(sessions: [session])
    let loop = ContextTrailLoop(repository: repository)
    let xcode = try contextApplication("dev.xcode", "Xcode")
    let safari = try contextApplication("com.apple.safari", "Safari")

    #expect(try await loop.observe(xcode, at: Date(timeIntervalSince1970: 2)) == nil)
    _ = try await loop.setEnabled(true)
    #expect(try await loop.observe(xcode, at: Date(timeIntervalSince1970: 3)) != nil)
    #expect(try await loop.observe(xcode, at: Date(timeIntervalSince1970: 4)) == nil)
    #expect(try await loop.observe(safari, at: Date(timeIntervalSince1970: 5)) != nil)

    let episodes = try await loop.currentEpisodes(at: Date(timeIntervalSince1970: 6))
    #expect(episodes.map(\.application.applicationName) == ["Xcode", "Safari"])
    #expect(try await repository.contextTrailEvents().count == 2)

    await repository.seed(sessions: [FocusSession(
        id: session.id,
        intentionID: session.intentionID,
        startedAt: session.startedAt,
        state: .paused
    )])
    #expect(try await loop.observe(xcode, at: Date(timeIntervalSince1970: 7)) == nil)
}

@Test func disablingContextTrailErasesRetainedEvents() async throws {
    let repository = ContextTrailRepository()
    let session = FocusSession(intentionID: UUID(), startedAt: .distantPast)
    await repository.seed(sessions: [session])
    let loop = ContextTrailLoop(repository: repository)
    _ = try await loop.setEnabled(true)
    _ = try await loop.observe(
        contextApplication("dev.editor", "Editor"),
        at: Date(timeIntervalSince1970: 20)
    )

    let settings = try await loop.setEnabled(false)

    #expect(settings.mode == .privateMode)
    #expect(try await repository.contextTrailEvents().isEmpty)
    #expect(try await loop.currentEpisodes(at: Date(timeIntervalSince1970: 21)).isEmpty)
}

@Test func contextTrailReferenceIsBoundedChronologicalAndPrivateSafe() async throws {
    let repository = ContextTrailRepository()
    let session = FocusSession(intentionID: UUID(), startedAt: .distantPast)
    await repository.seed(sessions: [session])
    let provider = ContextTrailReferenceProvider(
        repository: repository,
        now: { Date(timeIntervalSince1970: 100) }
    )
    #expect(try await provider.references().isEmpty)

    try await repository.save(
        contextTrailSettings: ContextTrailSettings(mode: .focusTrail, retentionHours: 8)
    )
    for (index, name) in ["One", "Two", "Three", "Four", "Five", "Six", "Seven"].enumerated() {
        try await repository.append(contextTrailEvent: ContextTrailEvent(
            intentionID: session.intentionID,
            focusSessionID: session.id,
            observedAt: Date(timeIntervalSince1970: Double(index + 1)),
            application: contextApplication("dev.\(name.lowercased())", name)
        ))
    }

    #expect(try await provider.references() == [
        "Context trail — … → Two → Three → Four → Five → Six → Seven",
    ])
}

private func contextApplication(_ bundle: String, _ name: String) throws -> ApplicationContext {
    try ApplicationContext(bundleIdentifier: bundle, applicationName: name)
}

private func contextEvent(
    _ index: Int,
    application: ApplicationContext,
    intentionID: UUID,
    sessionID: UUID,
    absoluteTime: Date? = nil
) -> ContextTrailEvent {
    ContextTrailEvent(
        id: UUID(),
        intentionID: intentionID,
        focusSessionID: sessionID,
        observedAt: absoluteTime ?? Date(timeIntervalSince1970: Double(index)),
        application: application
    )
}

private actor ContextTrailRepository: ThoughtRepository {
    private var settingsValue = ContextTrailSettings()
    private var eventValues: [ContextTrailEvent] = []
    private var sessionValues: [FocusSession] = []

    func seed(sessions: [FocusSession]) { sessionValues = sessions }
    func save(contextTrailSettings: ContextTrailSettings) async throws {
        settingsValue = contextTrailSettings
    }
    func contextTrailSettings() async throws -> ContextTrailSettings { settingsValue }
    func append(contextTrailEvent: ContextTrailEvent) async throws {
        eventValues.removeAll { $0.id == contextTrailEvent.id }
        eventValues.append(contextTrailEvent)
    }
    func contextTrailEvents() async throws -> [ContextTrailEvent] {
        eventValues.sorted(by: ContextTrailPolicy.eventComesBefore)
    }
    func replace(contextTrailEvents: [ContextTrailEvent]) async throws {
        eventValues = contextTrailEvents
    }
    func focusSessions() async throws -> [FocusSession] { sessionValues }
    func save(capture: RawCapture) async throws {}
    func save(proposal: ClarificationProposal) async throws {}
    func save(intention: Intention) async throws {}
    func captures(disposition: Disposition) async throws -> [RawCapture] { [] }
    func intention(id: UUID) async throws -> Intention? { nil }
    func openIntentions() async throws -> [Intention] { [] }
    func proposal(captureID: UUID) async throws -> ClarificationProposal? { nil }
}
