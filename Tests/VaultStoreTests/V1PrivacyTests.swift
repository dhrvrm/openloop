import ADHDCore
import Foundation
import Testing
@testable import VaultStore

@Suite("v1 privacy")
struct V1PrivacyTests {
    private let key = Data(repeating: 0x73, count: 32)

    @Test func retentionRemovesOnlyOldTerminalEvidenceAndPersistsThePolicy() async throws {
        let directory = temporaryV1Directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try EncryptedThoughtRepository(directory: directory, keyData: key)
        let now = Date(timeIntervalSince1970: 200 * 24 * 60 * 60)
        let oldDate = now.addingTimeInterval(-100 * 24 * 60 * 60)
        let terminal = try RawCapture(createdAt: oldDate, text: "old finished marker")
        let open = try RawCapture(createdAt: oldDate, text: "old open marker")
        try await repository.save(capture: terminal)
        try await repository.save(capture: open)
        try await repository.save(intention: Intention(
            id: terminal.id,
            sourceCaptureID: terminal.id,
            desiredOutcome: "Finished",
            nextAction: "Done",
            state: .closed,
            createdAt: oldDate,
            returnPacket: nil
        ))
        try await repository.save(memoryRecords: [MemoryRecord(
            kind: .decision,
            statement: "old finished memory",
            confidence: 1,
            evidence: [MemoryEvidence(
                evidenceID: RecallEvidenceID(kind: .capture, id: terminal.id),
                excerpt: terminal.text,
                occurredAt: oldDate
            )],
            createdAt: oldDate,
            updatedAt: oldDate
        )])
        try await repository.save(intention: Intention(
            id: open.id,
            sourceCaptureID: open.id,
            desiredOutcome: "Still open",
            nextAction: "Continue",
            state: .open,
            createdAt: oldDate,
            returnPacket: nil
        ))

        let result = try await repository.applyRetention(.thirtyDays, at: now)

        #expect(result == RetentionResult(removedCaptures: 1, removedIntentions: 1))
        #expect(try await repository.capture(id: terminal.id) == nil)
        #expect(try await repository.capture(id: open.id) == open)
        #expect(try await repository.memoryRecords().isEmpty)
        let reopened = try EncryptedThoughtRepository(directory: directory, keyData: key)
        #expect(try await reopened.retentionPolicy() == .thirtyDays)
    }

    @Test func backupIsCiphertextAndResetClearsTheLiveVault() async throws {
        let directory = temporaryV1Directory()
        let backupDirectory = temporaryV1Directory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: backupDirectory)
        }
        let repository = try EncryptedThoughtRepository(directory: directory, keyData: key)
        let marker = "private v1 backup marker"
        let capture = try RawCapture(createdAt: .now, text: marker)
        try await repository.save(capture: capture)
        let backupURL = backupDirectory.appendingPathComponent("openloop.vault")

        try await repository.exportEncryptedBackup(to: backupURL)

        let backupData = try Data(contentsOf: backupURL)
        #expect(backupData.range(of: Data(marker.utf8)) == nil)
        let backupReader = try EncryptedThoughtRepository(directory: backupDirectory, keyData: key)
        #expect(try await backupReader.capture(id: capture.id) == capture)

        try await repository.resetAllData()
        let summary = try await repository.privacySummary()
        #expect(summary.captureCount == 0)
        #expect(summary.openIntentionCount == 0)
        #expect(summary.completedIntentionCount == 0)
        #expect(summary.memoryCount == 0)
        #expect(summary.contextEventCount == 0)
    }
}

private func temporaryV1Directory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("openloop-v1-\(UUID().uuidString)", isDirectory: true)
}
