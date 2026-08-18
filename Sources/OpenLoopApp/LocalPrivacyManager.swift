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

    init(repository: EncryptedThoughtRepository, recallIndex: EncryptedRecallIndexStore) {
        self.repository = repository
        self.recallIndex = recallIndex
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
    }
}
