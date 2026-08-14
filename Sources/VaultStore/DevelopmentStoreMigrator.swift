import Foundation
import LocalStore

public enum MigrationResult: Equatable, Sendable {
    case notNeeded
    case imported(count: Int)
    case vaultAlreadyInitialized
}

public struct DevelopmentStoreMigrator: Sendable {
    public init() {}

    public func migrateIfNeeded(
        from legacyDirectory: URL,
        to vault: EncryptedThoughtRepository
    ) async throws -> MigrationResult {
        let legacyFile = legacyDirectory.appendingPathComponent("thought-loop.json")
        guard FileManager.default.fileExists(atPath: legacyFile.path) else { return .notNeeded }
        guard await vault.isEmpty else { return .vaultAlreadyInitialized }

        let legacy = try JSONFileThoughtRepository(directory: legacyDirectory)
        let snapshot = await legacy.developmentSnapshot()
        try await vault.importDevelopmentSnapshot(snapshot)
        let verified = try await vault.verifyPersistedSnapshot()
        guard verified.captures == snapshot.captures.count,
              verified.proposals == snapshot.proposals.count,
              verified.intentions == snapshot.intentions.count else {
            throw VaultStoreError.corruptPayload
        }
        try FileManager.default.removeItem(at: legacyFile)
        return .imported(count: verified.captures)
    }
}
