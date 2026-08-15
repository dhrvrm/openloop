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

@Test func resurfacingLoopSuggestsOnlyEligibleOpenRulesAndRecordsShownCooldown() async throws {
    let repository = ResurfacingRepository()
    let application = try ApplicationContext(
        bundleIdentifier: "dev.openloop.Editor", applicationName: "Editor"
    )
    let linked = openIntention(marker: "linked", seconds: 1)
    let notLinked = openIntention(marker: "not linked", seconds: 2)
    let closed = Intention(
        id: UUID(), sourceCaptureID: UUID(), desiredOutcome: "Closed",
        nextAction: "Done", state: .closed,
        createdAt: Date(timeIntervalSince1970: 3), returnPacket: nil
    )
    for intention in [linked, notLinked, closed] {
        try await repository.save(intention: intention)
    }
    for intention in [linked, closed] {
        try await repository.save(resurfacingRule: ResurfacingRule(
            intentionID: intention.id,
            application: application,
            createdAt: Date(timeIntervalSince1970: 5)
        ))
    }
    let now = Date(timeIntervalSince1970: 1_000)
    let context = ContextEvent(observedAt: now, application: application)
    let loop = ResurfacingLoop(repository: repository)

    let first = try await loop.suggest(for: context, at: now)
    let repeated = try await loop.suggest(for: context, at: now.addingTimeInterval(60))

    #expect(first.map(\.intentionID) == [linked.id])
    #expect(repeated.isEmpty)
    let events = try await repository.suggestionEvents()
    #expect(events.count == 1)
    #expect(events[0].intentionID == linked.id)
    #expect(events[0].kind == .shown)
    #expect(events[0].application == application)
}

@Test func resurfacingLoopRecordsStartedLaterAndNeverFeedbackWithoutPartialErrors() async throws {
    let repository = ResurfacingRepository()
    let application = try ApplicationContext(
        bundleIdentifier: "dev.openloop.Editor", applicationName: "Editor"
    )
    let started = openIntention(marker: "started", seconds: 1)
    let deferred = openIntention(marker: "deferred", seconds: 2)
    let silenced = openIntention(marker: "silenced", seconds: 3)
    for intention in [started, deferred, silenced] {
        try await repository.save(intention: intention)
        try await repository.save(resurfacingRule: ResurfacingRule(
            intentionID: intention.id,
            application: application,
            createdAt: Date(timeIntervalSince1970: 5)
        ))
    }
    let loop = ResurfacingLoop(repository: repository)
    let now = Date(timeIntervalSince1970: 2_000)

    _ = try await loop.recordFeedback(
        .started, intentionID: started.id, application: application, at: now
    )
    _ = try await loop.recordFeedback(
        .later, intentionID: deferred.id, application: application,
        at: now.addingTimeInterval(1)
    )
    _ = try await loop.recordFeedback(
        .never, intentionID: silenced.id, application: application,
        at: now.addingTimeInterval(2)
    )
    await #expect(throws: ResurfacingLoopError.intentionNotFound) {
        try await loop.recordFeedback(
            .later, intentionID: UUID(), application: application, at: now
        )
    }

    let events = try await repository.suggestionEvents()
    #expect(events.map(\.kind) == [.started, .later, .never])
    #expect(events.count == 3)
    let rules = try await repository.resurfacingRules()
    let nextContext = ContextEvent(observedAt: now, application: application)
    let eligible = rules.filter {
        ResurfacingPolicy().isEligible(rule: $0, events: events, at: now)
    }
    let eligibleIDs = RelevanceScorer().suggestions(
        intentions: try await repository.openIntentions(),
        rules: eligible,
        context: nextContext
    ).map(\.intentionID)
    #expect(eligibleIDs == [started.id])
}

private func openIntention(marker: String, seconds: TimeInterval) -> Intention {
    Intention(
        id: UUID(), sourceCaptureID: UUID(), desiredOutcome: "\(marker) outcome",
        nextAction: "\(marker) next", state: .open,
        createdAt: Date(timeIntervalSince1970: seconds), returnPacket: nil
    )
}

private actor ResurfacingRepository: ThoughtRepository {
    var intentions: [UUID: Intention] = [:]
    var rules: [UUID: ResurfacingRule] = [:]
    var events: [UUID: SuggestionEvent] = [:]

    func save(capture: RawCapture) async throws {}
    func save(proposal: ClarificationProposal) async throws {}
    func save(intention: Intention) async throws { intentions[intention.id] = intention }
    func proposal(captureID: UUID) async throws -> ClarificationProposal? { nil }
    func captures(disposition: Disposition) async throws -> [RawCapture] { [] }
    func intention(id: UUID) async throws -> Intention? { intentions[id] }
    func openIntentions() async throws -> [Intention] {
        intentions.values.filter { $0.state != .closed && $0.state != .released }
    }
    func save(resurfacingRule: ResurfacingRule) async throws {
        rules[resurfacingRule.intentionID] = resurfacingRule
    }
    func deleteResurfacingRule(intentionID: UUID) async throws { rules[intentionID] = nil }
    func resurfacingRules() async throws -> [ResurfacingRule] {
        rules.values.sorted { $0.createdAt < $1.createdAt }
    }
    func append(suggestionEvent: SuggestionEvent) async throws {
        events[suggestionEvent.id] = suggestionEvent
    }
    func suggestionEvents() async throws -> [SuggestionEvent] {
        events.values.sorted {
            if $0.occurredAt == $1.occurredAt {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.occurredAt < $1.occurredAt
        }
    }
}
