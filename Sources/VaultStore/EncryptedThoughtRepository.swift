import ADHDCore
import CryptoKit
import Foundation
import LocalStore

private struct VaultSnapshot: Codable {
    var captures: [UUID: RawCapture] = [:]
    var proposals: [UUID: ClarificationProposal] = [:]
    var intentions: [UUID: Intention] = [:]
}

public enum VaultStoreError: Error, Equatable {
    case authenticationFailed
    case corruptPayload
    case invalidKeyLength(Int)
    case invalidMigrationReference
    case vaultNotEmpty
}

public struct VaultCounts: Equatable, Sendable {
    public let captures: Int
    public let proposals: Int
    public let intentions: Int
}

public actor EncryptedThoughtRepository: ThoughtRepository {
    public let fileURL: URL
    private static let authenticatedData = Data(
        "openloop.vault|schema=1|content=thought-loop".utf8
    )
    private let key: SymmetricKey
    private var snapshot: VaultSnapshot

    public init(directory: URL, keyData: Data) throws {
        guard keyData.count == 32 else { throw VaultStoreError.invalidKeyLength(keyData.count) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("openloop.vault")
        key = SymmetricKey(data: keyData)
        snapshot = VaultSnapshot()
        if FileManager.default.fileExists(atPath: fileURL.path) {
            snapshot = try Self.read(fileURL: fileURL, key: key)
        }
    }

    public init(directory: URL, keyProvider: any VaultKeyProvider) throws {
        try self.init(directory: directory, keyData: keyProvider.loadOrCreateKey())
    }

    public func save(capture: RawCapture) async throws {
        snapshot.captures[capture.id] = capture
        try persist()
    }

    public func save(proposal: ClarificationProposal) async throws {
        snapshot.proposals[proposal.captureID] = proposal
        try persist()
    }

    public func save(intention: Intention) async throws {
        snapshot.intentions[intention.id] = intention
        try persist()
    }

    public func proposal(captureID: UUID) async throws -> ClarificationProposal? {
        snapshot.proposals[captureID]
    }

    public func captures(disposition: Disposition) async throws -> [RawCapture] {
        snapshot.captures.values
            .filter { snapshot.proposals[$0.id]?.disposition == disposition }
            .sorted(by: Self.captureOrder)
    }

    public func intention(id: UUID) async throws -> Intention? { snapshot.intentions[id] }

    public func openIntentions() async throws -> [Intention] {
        snapshot.intentions.values
            .filter { $0.state != .closed && $0.state != .released }
            .sorted(by: Self.intentionOrder)
    }

    public var isEmpty: Bool {
        snapshot.captures.isEmpty && snapshot.proposals.isEmpty && snapshot.intentions.isEmpty
    }

    public var counts: VaultCounts {
        VaultCounts(
            captures: snapshot.captures.count,
            proposals: snapshot.proposals.count,
            intentions: snapshot.intentions.count
        )
    }

    public func importDevelopmentSnapshot(_ value: DevelopmentStoreSnapshot) throws {
        guard isEmpty else { throw VaultStoreError.vaultNotEmpty }
        let captureIDs = Set(value.captures.map(\.id))
        guard value.proposals.allSatisfy({ captureIDs.contains($0.captureID) }),
              value.intentions.allSatisfy({ captureIDs.contains($0.sourceCaptureID) }) else {
            throw VaultStoreError.invalidMigrationReference
        }
        snapshot.captures = Dictionary(uniqueKeysWithValues: value.captures.map { ($0.id, $0) })
        snapshot.proposals = Dictionary(uniqueKeysWithValues: value.proposals.map { ($0.captureID, $0) })
        snapshot.intentions = Dictionary(uniqueKeysWithValues: value.intentions.map { ($0.id, $0) })
        try persist()
    }

    public func verifyPersistedSnapshot() throws -> VaultCounts {
        let reopened = try Self.read(fileURL: fileURL, key: key)
        return VaultCounts(
            captures: reopened.captures.count,
            proposals: reopened.proposals.count,
            intentions: reopened.intentions.count
        )
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let plaintext = try encoder.encode(snapshot)
        let box = try AES.GCM.seal(
            plaintext,
            using: key,
            authenticating: Self.authenticatedData
        )
        guard let combined = box.combined else { throw VaultStoreError.corruptPayload }
        try combined.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private static func read(fileURL: URL, key: SymmetricKey) throws -> VaultSnapshot {
        do {
            let data = try Data(contentsOf: fileURL)
            let box = try AES.GCM.SealedBox(combined: data)
            let plaintext = try AES.GCM.open(box, using: key, authenticating: authenticatedData)
            do { return try JSONDecoder().decode(VaultSnapshot.self, from: plaintext) }
            catch { throw VaultStoreError.corruptPayload }
        } catch let error as VaultStoreError {
            throw error
        } catch {
            throw VaultStoreError.authenticationFailed
        }
    }

    private static func captureOrder(_ lhs: RawCapture, _ rhs: RawCapture) -> Bool {
        if lhs.createdAt == rhs.createdAt { return lhs.id.uuidString < rhs.id.uuidString }
        return lhs.createdAt < rhs.createdAt
    }

    private static func intentionOrder(_ lhs: Intention, _ rhs: Intention) -> Bool {
        if lhs.createdAt == rhs.createdAt { return lhs.id.uuidString < rhs.id.uuidString }
        return lhs.createdAt < rhs.createdAt
    }
}
