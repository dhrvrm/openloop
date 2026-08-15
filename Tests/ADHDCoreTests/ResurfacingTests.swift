import Foundation
import Testing
@testable import ADHDCore

@Test func applicationContextNormalizesIdentityAndRejectsMissingValues() throws {
    let context = try ApplicationContext(
        bundleIdentifier: "  COM.APPLE.XCODE  ",
        applicationName: "  Xcode  "
    )

    #expect(context.bundleIdentifier == "com.apple.xcode")
    #expect(context.applicationName == "Xcode")
    #expect(throws: ResurfacingValueError.emptyBundleIdentifier) {
        _ = try ApplicationContext(bundleIdentifier: "  ", applicationName: "Xcode")
    }
    #expect(throws: ResurfacingValueError.emptyApplicationName) {
        _ = try ApplicationContext(bundleIdentifier: "com.apple.dt.Xcode", applicationName: "")
    }
}

@Test func relevanceRequiresAnExplicitApplicationMatchAndExplainsItsWholeScore() throws {
    let xcode = try ApplicationContext(
        bundleIdentifier: "com.apple.dt.Xcode", applicationName: "Xcode"
    )
    let browser = try ApplicationContext(
        bundleIdentifier: "com.apple.Safari", applicationName: "Safari"
    )
    let matching = openIntention(marker: "matching", seconds: 1)
    let unrelated = openIntention(marker: "unrelated", seconds: 2)
    let rules = [
        ResurfacingRule(intentionID: matching.id, application: xcode, createdAt: .distantPast),
        ResurfacingRule(intentionID: unrelated.id, application: browser, createdAt: .distantPast),
    ]
    let context = ContextEvent(
        observedAt: Date(timeIntervalSince1970: 100), application: xcode
    )

    let suggestions = RelevanceScorer().suggestions(
        intentions: [unrelated, matching], rules: rules, context: context
    )

    #expect(suggestions.count == 1)
    #expect(suggestions[0].intentionID == matching.id)
    #expect(suggestions[0].score == 1)
    #expect(suggestions[0].contributions == [
        RelevanceContribution(
            label: "Application match",
            value: 1,
            explanation: "Linked to Xcode"
        )
    ])
    #expect(suggestions[0].why == "Linked to Xcode")
}

@Test func relevanceReturnsAtMostTwoWithStableOldestThenUUIDTies() throws {
    let context = try ApplicationContext(bundleIdentifier: "dev.openloop.Editor", applicationName: "Editor")
    let timestamp = Date(timeIntervalSince1970: 50)
    let ids = [
        UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
    ]
    let intentions = ids.map { id in
        Intention(
            id: id, sourceCaptureID: UUID(), desiredOutcome: id.uuidString,
            nextAction: "Continue", state: .open, createdAt: timestamp,
            returnPacket: nil
        )
    }
    let rules = intentions.map {
        ResurfacingRule(intentionID: $0.id, application: context, createdAt: timestamp)
    }

    let suggestions = RelevanceScorer().suggestions(
        intentions: Array(intentions.reversed()),
        rules: rules,
        context: ContextEvent(observedAt: timestamp, application: context)
    )

    #expect(suggestions.map(\.intentionID) == [ids[1], ids[2]])
    #expect(RelevanceScorer.threshold == 1)
    #expect(RelevanceScorer.maximumSuggestions == 2)
}

@Test func relevanceDoesNotPenalizeAnOldIntentionOrSuggestFinishedWork() throws {
    let application = try ApplicationContext(bundleIdentifier: "dev.openloop.Terminal", applicationName: "Terminal")
    let oldOpen = openIntention(marker: "old", seconds: -1_000_000)
    let closed = Intention(
        id: UUID(), sourceCaptureID: UUID(), desiredOutcome: "Closed",
        nextAction: "Nothing", state: .closed, createdAt: .distantFuture,
        returnPacket: nil
    )
    let rules = [oldOpen, closed].map {
        ResurfacingRule(intentionID: $0.id, application: application, createdAt: .distantPast)
    }

    let suggestions = RelevanceScorer().suggestions(
        intentions: [closed, oldOpen], rules: rules,
        context: ContextEvent(observedAt: .now, application: application)
    )

    #expect(suggestions.map(\.intentionID) == [oldOpen.id])
    #expect(suggestions[0].score == 1)
}

@Test func policyAppliesShownCooldownAndRestoresEligibilityAtTheBoundary() throws {
    let now = Date(timeIntervalSince1970: 20_000)
    let intentionID = UUID()
    let application = try ApplicationContext(bundleIdentifier: "dev.openloop.Editor", applicationName: "Editor")
    let rule = ResurfacingRule(intentionID: intentionID, application: application, createdAt: .distantPast)
    let shown = SuggestionEvent(
        intentionID: intentionID,
        occurredAt: now.addingTimeInterval(-ResurfacingPolicy.shownCooldown + 1),
        application: application,
        kind: .shown
    )
    let policy = ResurfacingPolicy()

    #expect(policy.isEligible(rule: rule, events: [], at: now))
    #expect(policy.isEligible(rule: rule, events: [shown], at: now) == false)
    #expect(policy.isEligible(
        rule: rule,
        events: [shown],
        at: shown.occurredAt.addingTimeInterval(ResurfacingPolicy.shownCooldown)
    ))
}

@Test func policyAppliesOneDayLaterAndPermanentNeverPerIntention() throws {
    let now = Date(timeIntervalSince1970: 100_000)
    let application = try ApplicationContext(bundleIdentifier: "dev.openloop.Editor", applicationName: "Editor")
    let firstID = UUID()
    let otherID = UUID()
    let first = ResurfacingRule(intentionID: firstID, application: application, createdAt: .distantPast)
    let other = ResurfacingRule(intentionID: otherID, application: application, createdAt: .distantPast)
    let later = SuggestionEvent(
        intentionID: firstID, occurredAt: now,
        application: application, kind: .later
    )
    let never = SuggestionEvent(
        intentionID: firstID, occurredAt: now.addingTimeInterval(1),
        application: application, kind: .never
    )
    let policy = ResurfacingPolicy()

    #expect(policy.isEligible(rule: first, events: [later], at: now) == false)
    #expect(policy.isEligible(
        rule: first,
        events: [later],
        at: now.addingTimeInterval(ResurfacingPolicy.laterSuppression)
    ))
    #expect(policy.isEligible(rule: first, events: [later, never], at: .distantFuture) == false)
    #expect(policy.isEligible(rule: other, events: [later, never], at: now))
}

private func openIntention(marker: String, seconds: TimeInterval) -> Intention {
    Intention(
        id: UUID(), sourceCaptureID: UUID(), desiredOutcome: "\(marker) outcome",
        nextAction: "\(marker) next", state: .open,
        createdAt: Date(timeIntervalSince1970: seconds), returnPacket: nil
    )
}
