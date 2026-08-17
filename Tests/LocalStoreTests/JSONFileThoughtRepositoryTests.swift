import ADHDCore
import Foundation
import Testing
@testable import LocalStore

private struct LegacySnapshot: Codable {
    var captures: [UUID: RawCapture]
    var intentions: [UUID: Intention]
}

@Test func savedThoughtsSurviveRepositoryRestart() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let capture = try RawCapture(createdAt: .now, text: "Email the revised flow")
    let intention = Intention(
        id: UUID(),
        sourceCaptureID: capture.id,
        desiredOutcome: "Riya receives the new flow",
        nextAction: "Open the latest Figma file",
        state: .open,
        createdAt: .now,
        returnPacket: nil
    )
    let proposal = try ClarificationProposal(
        captureID: capture.id,
        disposition: .later,
        desiredOutcome: nil,
        nextAction: nil,
        confidence: 1
    )

    let writer = try JSONFileThoughtRepository(directory: directory)
    try await writer.save(capture: capture)
    try await writer.save(proposal: proposal)
    try await writer.save(intention: intention)

    let reader = try JSONFileThoughtRepository(directory: directory)
    #expect(try await reader.proposal(captureID: capture.id) == proposal)
    #expect(try await reader.captures(disposition: .later) == [capture])
    #expect(try await reader.intention(id: intention.id) == intention)
    #expect(try await reader.openIntentions() == [intention])
}

@Test func focusSessionAndIntentionPairSurviveRepositoryRestart() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let id = UUID()
    let intention = Intention(
        id: id,
        sourceCaptureID: id,
        desiredOutcome: "Finish the recovery flow",
        nextAction: "Open the focus view",
        state: .active,
        createdAt: Date(timeIntervalSince1970: 10),
        returnPacket: nil
    )
    var session = FocusSession(
        id: UUID(),
        intentionID: id,
        startedAt: Date(timeIntervalSince1970: 20)
    )
    try session.pause(at: Date(timeIntervalSince1970: 50))
    let writer = try JSONFileThoughtRepository(directory: directory)

    try await writer.save(intention: intention, focusSession: session)

    let reader = try JSONFileThoughtRepository(directory: directory)
    #expect(try await reader.intention(id: id) == intention)
    #expect(try await reader.focusSession(id: session.id) == session)
    #expect(try await reader.focusSessions() == [session])
}

@Test func legacySnapshotWithoutClarificationsStillLoads() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let capture = try RawCapture(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        createdAt: Date(timeIntervalSince1970: 10),
        text: "An existing capture"
    )
    let legacy = LegacySnapshot(captures: [capture.id: capture], intentions: [:])
    let data = try JSONEncoder().encode(legacy)
    try data.write(to: directory.appendingPathComponent("thought-loop.json"))

    let repository = try JSONFileThoughtRepository(directory: directory)

    #expect(try await repository.proposal(captureID: capture.id) == nil)
    #expect(try await repository.captures(disposition: .unclear).isEmpty)
    #expect(try await repository.transcriptionCorrections().isEmpty)
}

@Test func transcriptionCorrectionsSurviveDevelopmentRestartWithStableOrdering() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let timestamp = Date(timeIntervalSince1970: 10)
    let later = try TranscriptionCorrection(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        recognized: "open ex code", corrected: "Open Xcode", createdAt: timestamp
    )
    let earlier = try TranscriptionCorrection(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        recognized: "call cool van", corrected: "Call Kuvam", createdAt: timestamp
    )
    let writer = try JSONFileThoughtRepository(directory: directory)

    try await writer.save(transcriptionCorrection: later)
    try await writer.save(transcriptionCorrection: earlier)

    let reader = try JSONFileThoughtRepository(directory: directory)
    #expect(try await reader.transcriptionCorrections() == [earlier, later])
}

@Test func dispositionReadsHaveStableOrderingForEqualTimestamps() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let date = Date(timeIntervalSince1970: 10)
    let laterID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let earlierID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let laterCapture = try RawCapture(id: laterID, createdAt: date, text: "Second")
    let earlierCapture = try RawCapture(id: earlierID, createdAt: date, text: "First")
    let repository = try JSONFileThoughtRepository(directory: directory)

    for capture in [laterCapture, earlierCapture] {
        try await repository.save(capture: capture)
        let proposal = try ClarificationProposal(
            captureID: capture.id,
            disposition: .later,
            desiredOutcome: nil,
            nextAction: nil,
            confidence: 1
        )
        try await repository.save(proposal: proposal)
    }

    #expect(try await repository.captures(disposition: .later) == [earlierCapture, laterCapture])
}

@Test func corruptSnapshotIsReportedInsteadOfDiscarded() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("not-json".utf8).write(to: directory.appendingPathComponent("thought-loop.json"))

    #expect(throws: JSONFileThoughtRepositoryError.corruptSnapshot) {
        try JSONFileThoughtRepository(directory: directory)
    }
}

@Test func twoDevelopmentRepositoriesPersistOnlyOneCurrentFocus() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let writer = try JSONFileThoughtRepository(directory: directory)
    let firstIntention = localTestIntention()
    let secondIntention = localTestIntention()
    try await writer.save(intention: firstIntention)
    try await writer.save(intention: secondIntention)
    let first = try JSONFileThoughtRepository(directory: directory)
    let second = try JSONFileThoughtRepository(directory: directory)
    let date = Date(timeIntervalSince1970: 100)

    async let firstStarted = attemptLocalStart(firstIntention.id, repository: first, at: date)
    async let secondStarted = attemptLocalStart(secondIntention.id, repository: second, at: date)
    let outcomes = await [firstStarted, secondStarted]

    #expect(outcomes.filter { $0 }.count == 1)
    let reopened = try JSONFileThoughtRepository(directory: directory)
    #expect(try await reopened.focusSessions().filter {
        $0.state == .active || $0.state == .paused
    }.count == 1)
    #expect(try await reopened.openIntentions().filter { $0.state == .active }.count == 1)
}

@Test func standaloneDevelopmentFocusSaveRejectsASecondCurrentSession() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = try JSONFileThoughtRepository(directory: directory)
    let first = FocusSession(intentionID: UUID(), startedAt: .now)
    let second = FocusSession(intentionID: UUID(), startedAt: .now)
    try await repository.save(focusSession: first)

    await #expect(throws: ThoughtRepositoryFocusError.currentFocusExists(first.intentionID)) {
        try await repository.save(focusSession: second)
    }
}

@Test func resurfacingRulesAndStableHistorySurviveDevelopmentRepositoryRestart() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let application = try ApplicationContext(
        bundleIdentifier: "dev.openloop.distinct-editor",
        applicationName: "Distinct Editor"
    )
    let intentionID = UUID()
    let original = ResurfacingRule(
        intentionID: intentionID,
        application: application,
        createdAt: Date(timeIntervalSince1970: 1)
    )
    let updated = ResurfacingRule(
        intentionID: intentionID,
        application: application,
        createdAt: Date(timeIntervalSince1970: 2)
    )
    let timestamp = Date(timeIntervalSince1970: 10)
    let laterID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let earlierID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let laterEvent = SuggestionEvent(
        id: laterID, intentionID: intentionID, occurredAt: timestamp,
        application: application, kind: .later
    )
    let shownEvent = SuggestionEvent(
        id: earlierID, intentionID: intentionID, occurredAt: timestamp,
        application: application, kind: .shown
    )
    let writer = try JSONFileThoughtRepository(directory: directory)

    try await writer.save(resurfacingRule: original)
    try await writer.save(resurfacingRule: updated)
    try await writer.append(suggestionEvent: laterEvent)
    try await writer.append(suggestionEvent: shownEvent)

    let reader = try JSONFileThoughtRepository(directory: directory)
    #expect(try await reader.resurfacingRules() == [updated])
    #expect(try await reader.suggestionEvents() == [shownEvent, laterEvent])

    try await reader.deleteResurfacingRule(intentionID: intentionID)
    let afterDelete = try JSONFileThoughtRepository(directory: directory)
    #expect(try await afterDelete.resurfacingRules().isEmpty)
    #expect(try await afterDelete.suggestionEvents() == [shownEvent, laterEvent])
}

private func attemptLocalStart(
    _ id: UUID,
    repository: JSONFileThoughtRepository,
    at date: Date
) async -> Bool {
    do {
        _ = try await FocusLoop(repository: repository).start(id, at: date)
        return true
    } catch {
        return false
    }
}

private func localTestIntention() -> Intention {
    let id = UUID()
    return Intention(
        id: id,
        sourceCaptureID: id,
        desiredOutcome: "Test local focus",
        nextAction: "Begin",
        state: .open,
        createdAt: Date(timeIntervalSince1970: 1),
        returnPacket: nil
    )
}
