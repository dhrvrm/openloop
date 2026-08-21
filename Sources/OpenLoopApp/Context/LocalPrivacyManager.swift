import ADHDCore
import Foundation
import VaultStore

protocol PrivacyManaging: Sendable {
    func summary() async throws -> PrivacyDataSummary
    func retentionPolicy() async throws -> PrivacyRetentionPolicy
    func applyRetention(_ policy: PrivacyRetentionPolicy, at date: Date) async throws
        -> RetentionResult
    func createEncryptedBackup(at destination: URL) async throws
    func resetAllData() async throws
}

actor LocalPrivacyManager: PrivacyManaging {
    private let repository: EncryptedThoughtRepository
    private let recallIndex: EncryptedRecallIndexStore
    private let managedDirectories: [URL]

    init(
        repository: EncryptedThoughtRepository,
        recallIndex: EncryptedRecallIndexStore,
        managedDirectories: [URL] = []
    ) {
        self.repository = repository
        self.recallIndex = recallIndex
        self.managedDirectories = managedDirectories
    }

    func summary() async throws -> PrivacyDataSummary {
        try await repository.privacySummary()
    }

    func retentionPolicy() async throws -> PrivacyRetentionPolicy {
        try await repository.retentionPolicy()
    }

    func applyRetention(
        _ policy: PrivacyRetentionPolicy,
        at date: Date
    ) async throws -> RetentionResult {
        let result = try await repository.applyRetention(policy, at: date)
        try await recallIndex.discard()
        return result
    }

    func createEncryptedBackup(at destination: URL) async throws {
        try await repository.exportEncryptedBackup(to: destination)
    }

    func resetAllData() async throws {
        try await repository.resetAllData()
        try await recallIndex.discard()
        for directory in managedDirectories where FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}
