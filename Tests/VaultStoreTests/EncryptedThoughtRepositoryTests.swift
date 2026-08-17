import ADHDCore
import CryptoKit
import Foundation
import LocalStore
import Security
import Testing
@testable import VaultStore

private let fixedKey = Data(repeating: 0x42, count: 32)

private struct SchemaOneVaultSnapshot: Codable {
    var captures: [UUID: RawCapture]
    var proposals: [UUID: ClarificationProposal]
    var intentions: [UUID: Intention]
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
}

@Test func keychainProviderReturnsTheSame32ByteKey() throws {
    let service = "dev.openloop.tests.\(UUID().uuidString)"
    let account = "root-key"
    let deleteQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
    ]
    defer { SecItemDelete(deleteQuery as CFDictionary) }
    let provider = KeychainVaultKeyProvider(service: service, account: account)

    let first = try provider.loadOrCreateKey()
    let second = try provider.loadOrCreateKey()

    #expect(first.count == 32)
    #expect(first == second)
}

@Test func encryptedThoughtsSurviveRestartWithoutPlaintext() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let capture = try RawCapture(createdAt: .now, text: "private launch intention")
    let proposal = try ClarificationProposal(
        captureID: capture.id, disposition: .later, desiredOutcome: nil,
        nextAction: nil, confidence: 1
    )
    let writer = try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)
    try await writer.save(capture: capture)
    try await writer.save(proposal: proposal)

    let data = try Data(contentsOf: directory.appendingPathComponent("openloop.vault"))
    #expect(data.range(of: Data(capture.text.utf8)) == nil)

    let reader = try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)
    #expect(try await reader.captures(disposition: .later) == [capture])
    #expect(try await reader.proposal(captureID: capture.id) == proposal)
}

@Test func clarificationCorrectionSurvivesEncryptedRestart() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let capture = try RawCapture(createdAt: Date(timeIntervalSince1970: 10), text: "Riya prefers email")
    let action = try ClarificationProposal(
        captureID: capture.id,
        disposition: .action,
        desiredOutcome: "Reply to Riya",
        nextAction: "Open Riya's message",
        confidence: 0.7
    )
    let memory = try ClarificationProposal(
        captureID: capture.id,
        disposition: .memory,
        desiredOutcome: nil,
        nextAction: nil,
        confidence: 1
    )
    var intention = Intention(
        id: capture.id,
        sourceCaptureID: capture.id,
        desiredOutcome: "Reply to Riya",
        nextAction: "Open Riya's message",
        state: .open,
        createdAt: capture.createdAt,
        returnPacket: nil
    )
    try intention.transition(to: .released)
    let correction = ClarificationCorrection(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
        captureID: capture.id,
        reviewedAt: Date(timeIntervalSince1970: 20),
        previousProposal: action,
        proposal: memory
    )
    let writer = try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)
    try await writer.save(capture: capture)
    try await writer.save(proposal: action)

    try await writer.apply(clarificationCorrection: correction, intention: intention)

    let vaultData = try Data(contentsOf: directory.appendingPathComponent("openloop.vault"))
    #expect(vaultData.range(of: Data("Open Riya's message".utf8)) == nil)
    let reader = try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)
    #expect(try await reader.proposal(captureID: capture.id) == memory)
    #expect(try await reader.intention(id: capture.id) == intention)
    #expect(try await reader.clarificationCorrections(captureID: capture.id) == [correction])
}

@Test func encryptedFocusPairSurvivesRestartWithoutPacketPlaintext() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let id = UUID()
    let packet = try ReturnPacket(
        capturedAt: Date(timeIntervalSince1970: 30),
        justCompleted: "distinct completed recovery marker",
        nextAction: "distinct next recovery marker",
        blocker: "distinct blocker recovery marker",
        references: ["distinct-reference://recovery-marker"]
    )
    var intention = Intention(
        id: id,
        sourceCaptureID: id,
        desiredOutcome: "Recover exact encrypted context",
        nextAction: "Begin",
        state: .active,
        createdAt: Date(timeIntervalSince1970: 10),
        returnPacket: nil
    )
    try intention.interrupt(with: packet)
    var session = FocusSession(
        id: UUID(),
        intentionID: id,
        startedAt: Date(timeIntervalSince1970: 20)
    )
    try session.interrupt(at: packet.capturedAt)
    let writer = try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)

    try await writer.save(intention: intention, focusSession: session)

    let vaultData = try Data(contentsOf: directory.appendingPathComponent("openloop.vault"))
    for plaintext in [packet.justCompleted!, packet.nextAction, packet.blocker!, packet.references[0]] {
        #expect(vaultData.range(of: Data(plaintext.utf8)) == nil)
    }
    let reader = try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)
    #expect(try await reader.intention(id: id) == intention)
    #expect(try await reader.focusSession(id: session.id) == session)
    #expect(try await reader.focusSessions() == [session])
}

@Test func schemaOneVaultWithoutFocusSessionsStillOpens() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let capture = try RawCapture(createdAt: Date(timeIntervalSince1970: 1), text: "old vault")
    let snapshot = SchemaOneVaultSnapshot(
        captures: [capture.id: capture],
        proposals: [:],
        intentions: [:]
    )
    let plaintext = try JSONEncoder().encode(snapshot)
    let box = try AES.GCM.seal(
        plaintext,
        using: SymmetricKey(data: fixedKey),
        authenticating: Data("openloop.vault|schema=1|content=thought-loop".utf8)
    )
    try #require(box.combined).write(
        to: directory.appendingPathComponent("openloop.vault"),
        options: .atomic
    )

    let repository = try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)

    #expect(try await repository.focusSessions().isEmpty)
    #expect(try await repository.transcriptionCorrections().isEmpty)
    #expect(try await repository.memoryRecords().isEmpty)
    #expect(try await repository.contextTrailSettings() == ContextTrailSettings())
    #expect(try await repository.contextTrailEvents().isEmpty)
}

@Test func transcriptionCorrectionSurvivesEncryptedRestartWithoutPlaintext() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let correction = try TranscriptionCorrection(
        recognized: "distinct recognized voice marker",
        corrected: "Distinct Corrected Voice Marker",
        createdAt: Date(timeIntervalSince1970: 40)
    )
    let writer = try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)

    try await writer.save(transcriptionCorrection: correction)

    let reader = try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)
    #expect(try await reader.transcriptionCorrections() == [correction])
    let files = try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil
    )
    for file in files {
        let data = try Data(contentsOf: file)
        #expect(data.range(of: Data(correction.recognized.utf8)) == nil)
        #expect(data.range(of: Data(correction.corrected.utf8)) == nil)
    }
}

@Test func workingMemoryLedgerSurvivesEncryptedRestartWithoutPlaintext() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let record = encryptedMemoryRecord()
    let writer = try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)

    try await writer.save(memoryRecords: [record])

    let reader = try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)
    #expect(try await reader.memoryRecords() == [record])
    for file in try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    ) {
        let data = try Data(contentsOf: file)
        #expect(data.range(of: Data(record.statement.utf8)) == nil)
        #expect(data.range(of: Data(record.evidence[0].excerpt.utf8)) == nil)
    }
}

@Test func contextTrailSurvivesEncryptedRestartWithoutIdentityPlaintext() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let application = try ApplicationContext(
        bundleIdentifier: "dev.openloop.distinct-private-context",
        applicationName: "Distinct Private Context Editor"
    )
    let event = ContextTrailEvent(
        intentionID: UUID(),
        focusSessionID: UUID(),
        observedAt: Date(timeIntervalSince1970: 80),
        application: application
    )
    let settings = ContextTrailSettings(mode: .focusTrail, retentionHours: 6)
    let writer = try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)

    try await writer.save(contextTrailSettings: settings)
    try await writer.append(contextTrailEvent: event)

    let reader = try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)
    #expect(try await reader.contextTrailSettings() == settings)
    #expect(try await reader.contextTrailEvents() == [event])
    for file in try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    ) {
        let data = try Data(contentsOf: file)
        #expect(data.range(of: Data(application.bundleIdentifier.utf8)) == nil)
        #expect(data.range(of: Data(application.applicationName.utf8)) == nil)
    }
}

@Test func wrongKeyCannotOpenVault() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let writer = try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)
    try await writer.save(capture: RawCapture(createdAt: .now, text: "secret"))

    #expect(throws: VaultStoreError.authenticationFailed) {
        try EncryptedThoughtRepository(directory: directory, keyData: Data(repeating: 7, count: 32))
    }
}

@Test func tamperingIsReportedAsAuthenticationFailure() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)
    try await repository.save(capture: RawCapture(createdAt: .now, text: "secret"))
    let url = directory.appendingPathComponent("openloop.vault")
    var data = try Data(contentsOf: url)
    data[data.startIndex + 20] ^= 0xff
    try data.write(to: url)

    #expect(throws: VaultStoreError.authenticationFailed) {
        try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)
    }
}

@Test func developmentStoreMigratesOnceAndRemovesPlaintextAfterVerification() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let legacyDirectory = root.appendingPathComponent("legacy", isDirectory: true)
    let vaultDirectory = root.appendingPathComponent("vault", isDirectory: true)
    let legacy = try JSONFileThoughtRepository(directory: legacyDirectory)
    let capture = try RawCapture(createdAt: .now, text: "migrate this private thought")
    let proposal = try ClarificationProposal(
        captureID: capture.id, disposition: .memory, desiredOutcome: nil,
        nextAction: nil, confidence: 1
    )
    try await legacy.save(capture: capture)
    try await legacy.save(proposal: proposal)
    let vault = try EncryptedThoughtRepository(directory: vaultDirectory, keyData: fixedKey)

    let result = try await DevelopmentStoreMigrator().migrateIfNeeded(
        from: legacyDirectory,
        to: vault
    )

    #expect(result == .imported(count: 1))
    #expect(FileManager.default.fileExists(
        atPath: legacyDirectory.appendingPathComponent("thought-loop.json").path
    ) == false)
    #expect(FileManager.default.fileExists(
        atPath: legacyDirectory.appendingPathComponent("thought-loop.migrated").path
    ))
    await #expect(throws: JSONFileThoughtRepositoryError.storeMigrated) {
        try await legacy.save(capture: RawCapture(createdAt: .now, text: "too late"))
    }
    let reopened = try EncryptedThoughtRepository(directory: vaultDirectory, keyData: fixedKey)
    #expect(try await reopened.captures(disposition: .memory) == [capture])
    #expect(try await DevelopmentStoreMigrator().migrateIfNeeded(
        from: legacyDirectory,
        to: reopened
    ) == .notNeeded)
}

@Test func migrationLeavesPlaintextWhenLegacyStoreIsCorrupt() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let legacyDirectory = root.appendingPathComponent("legacy", isDirectory: true)
    try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
    let legacyFile = legacyDirectory.appendingPathComponent("thought-loop.json")
    try Data("not-json".utf8).write(to: legacyFile)
    let vault = try EncryptedThoughtRepository(
        directory: root.appendingPathComponent("vault"),
        keyData: fixedKey
    )

    await #expect(throws: JSONFileThoughtRepositoryError.corruptSnapshot) {
        try await DevelopmentStoreMigrator().migrateIfNeeded(from: legacyDirectory, to: vault)
    }
    #expect(FileManager.default.fileExists(atPath: legacyFile.path))
}

@Test func migrationDoesNotOverwriteAnInitializedVault() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let legacyDirectory = root.appendingPathComponent("legacy", isDirectory: true)
    let legacy = try JSONFileThoughtRepository(directory: legacyDirectory)
    try await legacy.save(capture: RawCapture(createdAt: .now, text: "legacy"))
    let legacyFile = legacyDirectory.appendingPathComponent("thought-loop.json")
    let vault = try EncryptedThoughtRepository(
        directory: root.appendingPathComponent("vault"),
        keyData: fixedKey
    )
    try await vault.save(capture: RawCapture(createdAt: .now, text: "current"))

    let result = try await DevelopmentStoreMigrator().migrateIfNeeded(
        from: legacyDirectory,
        to: vault
    )

    #expect(result == .vaultAlreadyInitialized)
    #expect(FileManager.default.fileExists(atPath: legacyFile.path))
    #expect(try await vault.empty() == false)
}

@Test func interruptedMigrationFinishesWhenVaultAlreadyContainsLegacySnapshot() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let legacyDirectory = root.appendingPathComponent("legacy", isDirectory: true)
    let legacy = try JSONFileThoughtRepository(directory: legacyDirectory)
    let capture = try RawCapture(createdAt: .now, text: "already imported")
    try await legacy.save(capture: capture)
    let snapshot = await legacy.developmentSnapshot()
    let vault = try EncryptedThoughtRepository(
        directory: root.appendingPathComponent("vault"),
        keyData: fixedKey
    )
    try await vault.importDevelopmentSnapshot(snapshot)

    let result = try await DevelopmentStoreMigrator().migrateIfNeeded(
        from: legacyDirectory,
        to: vault
    )

    #expect(result == .imported(count: 1))
    #expect(FileManager.default.fileExists(
        atPath: legacyDirectory.appendingPathComponent("thought-loop.json").path
    ) == false)
    #expect(try await vault.persistedDevelopmentSnapshot().captures == [capture])
}

@Test func twoRepositoryInstancesDoNotLoseUpdates() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)
    let second = try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)
    let firstCapture = try RawCapture(createdAt: .now, text: "first")
    let secondCapture = try RawCapture(createdAt: .now, text: "second")

    try await first.save(capture: firstCapture)
    try await second.save(capture: secondCapture)

    #expect(try await first.persistedDevelopmentSnapshot().captures.count == 2)
    #expect(try await second.persistedDevelopmentSnapshot().captures.count == 2)
}

@Test func duplicateMigrationIDsThrowInsteadOfTrapping() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)
    let capture = try RawCapture(createdAt: .now, text: "duplicate")
    let snapshot = DevelopmentStoreSnapshot(
        captures: [capture, capture], proposals: [], intentions: []
    )

    await #expect(throws: VaultStoreError.duplicateMigrationID) {
        try await repository.importDevelopmentSnapshot(snapshot)
    }
    #expect(try await repository.empty())
}

@Test func concurrentClarificationRecoveryConvergesOnOneIntention() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)
    let second = try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)
    let capture = try RawCapture(createdAt: .now, text: "todo: converge")
    try await first.save(capture: capture)
    let firstLoop = ThoughtLoop(repository: first, clarifier: TestActionClarifier())
    let secondLoop = ThoughtLoop(repository: second, clarifier: TestActionClarifier())

    async let firstRecovery = firstLoop.recoverUnclarifiedCaptures()
    async let secondRecovery = secondLoop.recoverUnclarifiedCaptures()
    _ = await (firstRecovery, secondRecovery)

    let intentions = try await first.openIntentions()
    #expect(intentions.count == 1)
    #expect(intentions.first?.id == capture.id)
}

@Test func concurrentFocusStartsPersistOnlyOneCurrentSession() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)
    let first = testIntention(state: .open)
    let second = testIntention(state: .open)
    try await repository.save(intention: first)
    try await repository.save(intention: second)
    let date = Date(timeIntervalSince1970: 100)

    async let firstStarted = attemptStart(first.id, repository: repository, at: date)
    async let secondStarted = attemptStart(second.id, repository: repository, at: date)
    let outcomes = await [firstStarted, secondStarted]

    #expect(outcomes.filter { $0 }.count == 1)
    let current = try await repository.focusSessions().filter {
        $0.state == .active || $0.state == .paused
    }
    #expect(current.count == 1)
    #expect(try await repository.openIntentions().filter { $0.state == .active }.count == 1)
}

@Test func concurrentFocusResumesPersistOnlyOneCurrentSession() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)
    let first = try interruptedPair(marker: "first")
    let second = try interruptedPair(marker: "second")
    try await repository.save(intention: first.intention, focusSession: first.session)
    try await repository.save(intention: second.intention, focusSession: second.session)
    let date = Date(timeIntervalSince1970: 200)

    async let firstResumed = attemptResume(first.intention.id, repository: repository, at: date)
    async let secondResumed = attemptResume(second.intention.id, repository: repository, at: date)
    let outcomes = await [firstResumed, secondResumed]

    #expect(outcomes.filter { $0 }.count == 1)
    let current = try await repository.focusSessions().filter {
        $0.state == .active || $0.state == .paused
    }
    #expect(current.count == 1)
    #expect(try await repository.openIntentions().filter { $0.state == .active }.count == 1)
}

@Test func standaloneEncryptedFocusSaveRejectsASecondCurrentSession() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)
    let first = FocusSession(intentionID: UUID(), startedAt: .now)
    let second = FocusSession(intentionID: UUID(), startedAt: .now)
    try await repository.save(focusSession: first)

    await #expect(throws: ThoughtRepositoryFocusError.currentFocusExists(first.intentionID)) {
        try await repository.save(focusSession: second)
    }
}

@Test func encryptedResurfacingStateSurvivesRestartWithoutContextPlaintext() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let application = try ApplicationContext(
        bundleIdentifier: "dev.openloop.distinct-secret-editor",
        applicationName: "Distinct Secret Editor"
    )
    let intentionID = UUID()
    let rule = ResurfacingRule(
        intentionID: intentionID,
        application: application,
        createdAt: Date(timeIntervalSince1970: 1)
    )
    let shown = SuggestionEvent(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        intentionID: intentionID,
        occurredAt: Date(timeIntervalSince1970: 20),
        application: application,
        kind: .shown
    )
    let never = SuggestionEvent(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        intentionID: intentionID,
        occurredAt: Date(timeIntervalSince1970: 20),
        application: application,
        kind: .never
    )
    let writer = try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)

    try await writer.save(resurfacingRule: rule)
    try await writer.append(suggestionEvent: shown)
    try await writer.append(suggestionEvent: never)

    let reader = try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)
    #expect(try await reader.resurfacingRules() == [rule])
    #expect(try await reader.suggestionEvents() == [never, shown])
    let distinctivePlaintext = [
        application.bundleIdentifier,
        application.applicationName,
        "Application match",
        "Linked to Distinct Secret Editor",
        SuggestionEventKind.never.rawValue,
    ]
    for file in try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    ) {
        let data = try Data(contentsOf: file)
        for value in distinctivePlaintext {
            #expect(data.range(of: Data(value.utf8)) == nil)
        }
    }

    try await reader.deleteResurfacingRule(intentionID: intentionID)
    let afterDelete = try EncryptedThoughtRepository(directory: directory, keyData: fixedKey)
    #expect(try await afterDelete.resurfacingRules().isEmpty)
    #expect(try await afterDelete.suggestionEvents() == [never, shown])
}

private func attemptStart(
    _ id: UUID,
    repository: EncryptedThoughtRepository,
    at date: Date
) async -> Bool {
    do {
        _ = try await FocusLoop(repository: repository).start(id, at: date)
        return true
    } catch {
        return false
    }
}

private func attemptResume(
    _ id: UUID,
    repository: EncryptedThoughtRepository,
    at date: Date
) async -> Bool {
    do {
        _ = try await FocusLoop(repository: repository).resume(id, at: date)
        return true
    } catch {
        return false
    }
}

private func testIntention(state: IntentionState) -> Intention {
    let id = UUID()
    return Intention(
        id: id,
        sourceCaptureID: id,
        desiredOutcome: "Test focus",
        nextAction: "Begin",
        state: state,
        createdAt: Date(timeIntervalSince1970: 1),
        returnPacket: nil
    )
}

private func interruptedPair(marker: String) throws -> (intention: Intention, session: FocusSession) {
    var intention = testIntention(state: .active)
    let packet = try ReturnPacket(
        capturedAt: Date(timeIntervalSince1970: 20),
        justCompleted: nil,
        nextAction: "Resume \(marker)",
        blocker: nil,
        references: []
    )
    try intention.interrupt(with: packet)
    var session = FocusSession(
        intentionID: intention.id,
        startedAt: Date(timeIntervalSince1970: 10)
    )
    try session.interrupt(at: packet.capturedAt)
    return (intention, session)
}

private func encryptedMemoryRecord() -> MemoryRecord {
    let id = UUID(uuidString: "60000000-0000-0000-0000-000000000001")!
    let date = Date(timeIntervalSince1970: 60)
    return MemoryRecord(
        id: id,
        kind: .decision,
        statement: "Distinct encrypted memory statement",
        confidence: 1,
        evidence: [MemoryEvidence(
            evidenceID: RecallEvidenceID(kind: .capture, id: id),
            excerpt: "decision: Distinct encrypted memory statement",
            occurredAt: date
        )],
        createdAt: date,
        updatedAt: date
    )
}

private struct TestActionClarifier: ClarificationProvider {
    func propose(for capture: RawCapture) async throws -> ClarificationProposal {
        try ClarificationProposal(
            captureID: capture.id,
            disposition: .action,
            desiredOutcome: "Converge",
            nextAction: "Begin",
            confidence: 1
        )
    }
}
