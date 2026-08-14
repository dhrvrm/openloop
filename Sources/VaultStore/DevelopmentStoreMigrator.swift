import Foundation
import LocalStore

public enum MigrationResult: Equatable, Sendable {
    case notNeeded
    case imported(count: Int)
    case vaultAlreadyInitialized
}

public enum MigrationError: Error, Equatable { case verificationFailed }

public struct DevelopmentStoreMigrator: Sendable {
    public init() {}

    public func migrateIfNeeded(
        from legacyDirectory: URL,
        to vault: EncryptedThoughtRepository
    ) async throws -> MigrationResult {
        let legacyFile = legacyDirectory.appendingPathComponent("thought-loop.json")
        guard FileManager.default.fileExists(atPath: legacyFile.path) else { return .notNeeded }
        let storeLock = try DevelopmentStoreLock(directory: legacyDirectory)
        try storeLock.lockExclusive()
        defer { storeLock.unlock() }

        let snapshot = try DevelopmentStoreSnapshot.load(from: legacyFile)
        if try await vault.empty() {
            try await vault.importDevelopmentSnapshot(snapshot)
        }
        let persisted = try await vault.persistedDevelopmentSnapshot()
        guard Self.contains(snapshot, in: persisted) else {
            return .vaultAlreadyInitialized
        }
        let marker = legacyDirectory.appendingPathComponent("thought-loop.migrated")
        try Data().write(to: marker, options: .atomic)
        try FileManager.default.removeItem(at: legacyFile)
        return .imported(count: snapshot.captures.count)
    }

    private static func contains(
        _ legacy: DevelopmentStoreSnapshot,
        in vault: DevelopmentStoreSnapshot
    ) -> Bool {
        legacy.captures.allSatisfy(vault.captures.contains)
            && legacy.proposals.allSatisfy(vault.proposals.contains)
            && legacy.intentions.allSatisfy(vault.intentions.contains)
    }
}
