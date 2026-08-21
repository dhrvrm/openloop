import ADHDCore
import Foundation
import Testing
import VaultStore
@testable import OpenLoopApp

private let privacyRootKey = Data(repeating: 0x61, count: 32)

@Test func fullResetRemovesVaultIndexStagedAudioAndModels() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let staging = root.appendingPathComponent("Meeting Staging", isDirectory: true)
    let models = root.appendingPathComponent("Models", isDirectory: true)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
    try Data("retained audio".utf8).write(to: staging.appendingPathComponent("meeting.m4a"))
    try Data("model bytes".utf8).write(to: models.appendingPathComponent("weights.bin"))

    let repository = try EncryptedThoughtRepository(directory: root, keyData: privacyRootKey)
    let capture = try RawCapture(createdAt: .now, text: "private reset marker")
    try await repository.save(capture: capture)
    let index = try EncryptedRecallIndexStore(directory: root, rootKeyData: privacyRootKey)
    try await index.save(RecallIndexSnapshot(
        providerIdentifier: "fixture",
        documents: [],
        vectors: []
    ))
    let manager = LocalPrivacyManager(
        repository: repository,
        recallIndex: index,
        managedDirectories: [staging, models]
    )

    try await manager.resetAllData()

    #expect(try await repository.allCaptures().isEmpty)
    #expect(try await index.load() == nil)
    #expect(!FileManager.default.fileExists(atPath: staging.path))
    #expect(!FileManager.default.fileExists(atPath: models.path))
}
