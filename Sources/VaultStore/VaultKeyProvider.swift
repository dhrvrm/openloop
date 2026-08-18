import Foundation
import Security

public protocol VaultKeyProvider: Sendable {
    func loadOrCreateKey() throws -> Data
}

public enum VaultKeyError: Error, Equatable {
    case invalidKeyLength(Int)
    case randomGeneration(OSStatus)
    case security(OSStatus)
    case unsafeLocalKeyFile
    case legacyVaultRequiresExplicitMigration
}

public struct LocalFileVaultKeyProvider: VaultKeyProvider, Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func loadOrCreateKey() throws -> Data {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return try loadExistingFile()
        }

        var key = Data(count: 32)
        let status = key.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw VaultKeyError.randomGeneration(status) }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try key.write(to: fileURL, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: fileURL.path
        )
        return key
    }

    private func loadExistingFile() throws -> Data {
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw VaultKeyError.unsafeLocalKeyFile
        }
        let key = try Data(contentsOf: fileURL)
        guard key.count == 32 else { throw VaultKeyError.invalidKeyLength(key.count) }
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: fileURL.path
        )
        return key
    }
}

public struct MigratingLocalVaultKeyProvider: VaultKeyProvider, Sendable {
    public let fileURL: URL
    private let fallback: any VaultKeyProvider

    public init(fileURL: URL, fallback: any VaultKeyProvider) {
        self.fileURL = fileURL
        self.fallback = fallback
    }

    public func loadOrCreateKey() throws -> Data {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return try loadExistingFile()
        }

        let key = try validate(fallback.loadOrCreateKey())
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try key.write(to: fileURL, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: fileURL.path
        )
        return key
    }

    private func loadExistingFile() throws -> Data {
        let values = try fileURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw VaultKeyError.unsafeLocalKeyFile
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: fileURL.path
        )
        return try validate(Data(contentsOf: fileURL))
    }

    private func validate(_ data: Data) throws -> Data {
        guard data.count == 32 else { throw VaultKeyError.invalidKeyLength(data.count) }
        return data
    }
}

public struct KeychainVaultKeyProvider: VaultKeyProvider, Sendable {
    public let service: String
    public let account: String

    public init(service: String = "dev.openloop.adhd.vault", account: String = "root-key") {
        self.service = service
        self.account = account
    }

    public func loadOrCreateKey() throws -> Data {
        let query = baseQuery.merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]) { _, new in new }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return try validate(data)
        }
        guard status == errSecItemNotFound else { throw VaultKeyError.security(status) }

        var key = Data(count: 32)
        let randomStatus = key.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard randomStatus == errSecSuccess else {
            throw VaultKeyError.randomGeneration(randomStatus)
        }
        let add = baseQuery.merging([
            kSecValueData as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]) { _, new in new }
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus == errSecDuplicateItem { return try loadExisting() }
        guard addStatus == errSecSuccess else { throw VaultKeyError.security(addStatus) }
        return key
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func loadExisting() throws -> Data {
        var query = baseQuery
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw VaultKeyError.security(status)
        }
        return try validate(data)
    }

    private func validate(_ data: Data) throws -> Data {
        guard data.count == 32 else { throw VaultKeyError.invalidKeyLength(data.count) }
        return data
    }
}
