import ADHDCore
import Foundation
import Testing
@testable import VaultStore

private let recallRootKey = Data(repeating: 0x31, count: 32)

@Test func encryptedRecallIndexStoreSurvivesRestartWithoutPlaintext() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let snapshot = recallSnapshot()
    let writer = try EncryptedRecallIndexStore(directory: directory, rootKeyData: recallRootKey)

    try await writer.save(snapshot)

    let bytes = try Data(contentsOf: writer.fileURL)
    #expect(bytes.range(of: Data(snapshot.documents[0].text.utf8)) == nil)
    let reader = try EncryptedRecallIndexStore(directory: directory, rootKeyData: recallRootKey)
    #expect(try await reader.load() == snapshot)
}

@Test func encryptedRecallIndexStoreTreatsWrongKeyAndCorruptionAsCacheMisses() async throws {
    let wrongKeyDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: wrongKeyDirectory) }
    let writer = try EncryptedRecallIndexStore(
        directory: wrongKeyDirectory, rootKeyData: recallRootKey
    )
    try await writer.save(recallSnapshot())

    let wrongKey = try EncryptedRecallIndexStore(
        directory: wrongKeyDirectory,
        rootKeyData: Data(repeating: 0x72, count: 32)
    )
    #expect(try await wrongKey.load() == nil)
    #expect(FileManager.default.fileExists(atPath: wrongKey.fileURL.path) == false)

    let corruptDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: corruptDirectory) }
    let corrupt = try EncryptedRecallIndexStore(
        directory: corruptDirectory, rootKeyData: recallRootKey
    )
    try Data("not-an-index".utf8).write(to: corrupt.fileURL)
    #expect(try await corrupt.load() == nil)
    #expect(FileManager.default.fileExists(atPath: corrupt.fileURL.path) == false)
    try await corrupt.discard()
}

private func recallSnapshot() -> RecallIndexSnapshot {
    RecallIndexSnapshot(
        providerIdentifier: "fixture-v1",
        documents: [RecallDocument(
            evidenceID: RecallEvidenceID(kind: .capture, id: UUID()),
            title: "Distinct evidence",
            text: "distinct private recall index marker",
            occurredAt: Date(timeIntervalSince1970: 10)
        )],
        vectors: [[0.25, 0.75]]
    )
}
