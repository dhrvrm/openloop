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
