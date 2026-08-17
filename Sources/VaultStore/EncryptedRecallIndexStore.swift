import ADHDCore
import CryptoKit
import Foundation

public enum EncryptedRecallIndexStoreError: Error, Equatable {
    case invalidRootKeyLength(Int)
    case invalidSealedBox
}

public actor EncryptedRecallIndexStore: RecallIndexStore {
    public nonisolated let fileURL: URL
    private static let authenticatedData = Data(
        "openloop.recall.index|schema=1|content=derived".utf8
    )
    private let key: SymmetricKey

    public init(directory: URL, rootKeyData: Data) throws {
        guard rootKeyData.count == 32 else {
            throw EncryptedRecallIndexStoreError.invalidRootKeyLength(rootKeyData.count)
        }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        fileURL = directory.appendingPathComponent("openloop-recall.index")
        key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: rootKeyData),
            salt: Data(),
            info: Data("openloop.recall.index.key.v1".utf8),
            outputByteCount: 32
        )
    }

    public func load() async throws -> RecallIndexSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let combined = try Data(contentsOf: fileURL)
            let box = try AES.GCM.SealedBox(combined: combined)
            let plaintext = try AES.GCM.open(
                box,
                using: key,
                authenticating: Self.authenticatedData
            )
            return try JSONDecoder().decode(RecallIndexSnapshot.self, from: plaintext)
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
    }

    public func save(_ snapshot: RecallIndexSnapshot) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let plaintext = try encoder.encode(snapshot)
        let box = try AES.GCM.seal(
            plaintext,
            using: key,
            authenticating: Self.authenticatedData
        )
        guard let combined = box.combined else {
            throw EncryptedRecallIndexStoreError.invalidSealedBox
        }
        try combined.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    public func discard() async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
