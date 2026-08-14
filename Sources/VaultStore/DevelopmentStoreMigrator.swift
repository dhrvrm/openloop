import Foundation
import LocalStore

public enum MigrationResult: Equatable, Sendable {
    case notNeeded
    case imported(count: Int)
    case vaultAlreadyInitialized
}

public enum MigrationError: Error, Equatable {
    case legacyChangedDuringMigration
    case verificationFailed
}

public struct DevelopmentStoreMigrator: Sendable {
    public init() {}

    public func migrateIfNeeded(
        from legacyDirectory: URL,
        to vault: EncryptedThoughtRepository
    ) async throws -> MigrationResult {
        let legacyFile = legacyDirectory.appendingPathComponent("thought-loop.json")
        guard FileManager.default.fileExists(atPath: legacyFile.path) else { return .notNeeded }
        guard try await vault.empty() else { return .vaultAlreadyInitialized }

        let originalData = try Data(contentsOf: legacyFile)
        let legacy = try JSONFileThoughtRepository(directory: legacyDirectory)
        let snapshot = await legacy.developmentSnapshot()
        try await vault.importDevelopmentSnapshot(snapshot)
        let verified = try await vault.persistedDevelopmentSnapshot()
        guard verified == snapshot else {
            try await vault.rollbackMigration()
            throw MigrationError.verificationFailed
        }
        guard try Data(contentsOf: legacyFile) == originalData else {
            try await vault.rollbackMigration()
            throw MigrationError.legacyChangedDuringMigration
        }
        try FileManager.default.removeItem(at: legacyFile)
        return .imported(count: verified.captures.count)
    }
}
