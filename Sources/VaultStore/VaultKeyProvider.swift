import Foundation
import Security

public protocol VaultKeyProvider: Sendable {
    func loadOrCreateKey() throws -> Data
}

public enum VaultKeyError: Error, Equatable {
    case invalidKeyLength(Int)
    case randomGeneration(OSStatus)
    case security(OSStatus)
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
