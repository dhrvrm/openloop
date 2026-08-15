import ADHDCore
import CryptoKit
import Darwin
import Foundation
import LocalStore

private struct VaultSnapshot: Codable {
    var captures: [UUID: RawCapture] = [:]
    var proposals: [UUID: ClarificationProposal] = [:]
    var intentions: [UUID: Intention] = [:]
    var focusSessions: [UUID: FocusSession] = [:]
    var resurfacingRules: [UUID: ResurfacingRule] = [:]
    var suggestionEvents: [UUID: SuggestionEvent] = [:]

    private enum CodingKeys: String, CodingKey {
        case captures
        case proposals
        case intentions
        case focusSessions
        case resurfacingRules
        case suggestionEvents
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        captures = try container.decode([UUID: RawCapture].self, forKey: .captures)
        proposals = try container.decodeIfPresent(
            [UUID: ClarificationProposal].self,
            forKey: .proposals
        ) ?? [:]
        intentions = try container.decode([UUID: Intention].self, forKey: .intentions)
        focusSessions = try container.decodeIfPresent(
            [UUID: FocusSession].self,
            forKey: .focusSessions
        ) ?? [:]
        resurfacingRules = try container.decodeIfPresent(
            [UUID: ResurfacingRule].self,
            forKey: .resurfacingRules
        ) ?? [:]
        suggestionEvents = try container.decodeIfPresent(
            [UUID: SuggestionEvent].self,
            forKey: .suggestionEvents
        ) ?? [:]
    }
}

public enum VaultStoreError: Error, Equatable {
    case authenticationFailed
    case corruptPayload
    case invalidKeyLength(Int)
    case invalidMigrationReference
    case duplicateMigrationID
    case lockingFailed(Int32)
    case vaultNotEmpty
}

public struct VaultCounts: Equatable, Sendable {
    public let captures: Int
    public let proposals: Int
    public let intentions: Int
}

public actor EncryptedThoughtRepository: ThoughtRepository {
    public let fileURL: URL
    private let lockURL: URL
    private static let authenticatedData = Data(
        "openloop.vault|schema=1|content=thought-loop".utf8
    )
    private let key: SymmetricKey
    private var snapshot: VaultSnapshot

    public init(directory: URL, keyData: Data) throws {
        guard keyData.count == 32 else { throw VaultStoreError.invalidKeyLength(keyData.count) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("openloop.vault")
        lockURL = directory.appendingPathComponent("openloop.vault.lock")
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
        try update { $0.captures[capture.id] = capture }
    }

    public func save(proposal: ClarificationProposal) async throws {
        try update { $0.proposals[proposal.captureID] = proposal }
    }

    public func save(proposal: ClarificationProposal, intention: Intention?) async throws {
        try update {
            $0.proposals[proposal.captureID] = proposal
            if let intention { $0.intentions[intention.id] = intention }
        }
    }

    public func save(intention: Intention) async throws {
        try update { $0.intentions[intention.id] = intention }
    }

    public func save(focusSession: FocusSession) async throws {
        try update {
            try Self.validateCurrentFocus(focusSession, in: $0)
            $0.focusSessions[focusSession.id] = focusSession
        }
    }

    public func save(intention: Intention, focusSession: FocusSession) async throws {
        try update {
            try Self.validateCurrentFocus(focusSession, in: $0)
            $0.intentions[intention.id] = intention
            $0.focusSessions[focusSession.id] = focusSession
        }
    }

    public func proposal(captureID: UUID) async throws -> ClarificationProposal? {
        try synchronize()
        return snapshot.proposals[captureID]
    }

    public func captures(disposition: Disposition) async throws -> [RawCapture] {
        try synchronize()
        return snapshot.captures.values
            .filter { snapshot.proposals[$0.id]?.disposition == disposition }
            .sorted(by: Self.captureOrder)
    }

    public func unclarifiedCaptures() async throws -> [RawCapture] {
        try synchronize()
        return snapshot.captures.values
            .filter { snapshot.proposals[$0.id] == nil }
            .sorted(by: Self.captureOrder)
    }

    public func capturesRequiringClarification() async throws -> [RawCapture] {
        try synchronize()
        let intentionSources = Set(snapshot.intentions.values.map(\.sourceCaptureID))
        return snapshot.captures.values
            .filter { capture in
                guard let proposal = snapshot.proposals[capture.id] else { return true }
                return proposal.disposition == .action && intentionSources.contains(capture.id) == false
            }
            .sorted(by: Self.captureOrder)
    }

    public func intention(id: UUID) async throws -> Intention? {
        try synchronize()
        return snapshot.intentions[id]
    }

    public func openIntentions() async throws -> [Intention] {
        try synchronize()
        return snapshot.intentions.values
            .filter { $0.state != .closed && $0.state != .released }
            .sorted(by: Self.intentionOrder)
    }

    public func focusSession(id: UUID) async throws -> FocusSession? {
        try synchronize()
        return snapshot.focusSessions[id]
    }

    public func focusSessions() async throws -> [FocusSession] {
        try synchronize()
        return snapshot.focusSessions.values.sorted(by: Self.focusSessionOrder)
    }

    public func save(resurfacingRule: ResurfacingRule) async throws {
        try update { $0.resurfacingRules[resurfacingRule.intentionID] = resurfacingRule }
    }

    public func deleteResurfacingRule(intentionID: UUID) async throws {
        try update { $0.resurfacingRules[intentionID] = nil }
    }

    public func resurfacingRules() async throws -> [ResurfacingRule] {
        try synchronize()
        return snapshot.resurfacingRules.values.sorted(by: Self.resurfacingRuleOrder)
    }

    public func append(suggestionEvent: SuggestionEvent) async throws {
        try update { $0.suggestionEvents[suggestionEvent.id] = suggestionEvent }
    }

    public func suggestionEvents() async throws -> [SuggestionEvent] {
        try synchronize()
        return snapshot.suggestionEvents.values.sorted(by: Self.suggestionEventOrder)
    }

    public func empty() throws -> Bool {
        try synchronize()
        return snapshot.captures.isEmpty
            && snapshot.proposals.isEmpty
            && snapshot.intentions.isEmpty
            && snapshot.focusSessions.isEmpty
            && snapshot.resurfacingRules.isEmpty
            && snapshot.suggestionEvents.isEmpty
    }

    public var counts: VaultCounts {
        VaultCounts(
            captures: snapshot.captures.count,
            proposals: snapshot.proposals.count,
            intentions: snapshot.intentions.count
        )
    }

    public func importDevelopmentSnapshot(_ value: DevelopmentStoreSnapshot) throws {
        let captureIDs = Set(value.captures.map(\.id))
        guard captureIDs.count == value.captures.count,
              Set(value.proposals.map(\.captureID)).count == value.proposals.count,
              Set(value.intentions.map(\.id)).count == value.intentions.count else {
            throw VaultStoreError.duplicateMigrationID
        }
        guard value.proposals.allSatisfy({ captureIDs.contains($0.captureID) }),
              value.intentions.allSatisfy({ captureIDs.contains($0.sourceCaptureID) }) else {
            throw VaultStoreError.invalidMigrationReference
        }
        try update { candidate in
            guard candidate.captures.isEmpty,
                  candidate.proposals.isEmpty,
                  candidate.intentions.isEmpty,
                  candidate.focusSessions.isEmpty,
                  candidate.resurfacingRules.isEmpty,
                  candidate.suggestionEvents.isEmpty else {
                throw VaultStoreError.vaultNotEmpty
            }
            candidate.captures = Dictionary(uniqueKeysWithValues: value.captures.map { ($0.id, $0) })
            candidate.proposals = Dictionary(uniqueKeysWithValues: value.proposals.map { ($0.captureID, $0) })
            candidate.intentions = Dictionary(uniqueKeysWithValues: value.intentions.map { ($0.id, $0) })
        }
    }

    public func verifyPersistedSnapshot() throws -> VaultCounts {
        let reopened = try withLock(exclusive: false) { try loadLatest() }
        return VaultCounts(
            captures: reopened.captures.count,
            proposals: reopened.proposals.count,
            intentions: reopened.intentions.count
        )
    }

    public func persistedDevelopmentSnapshot() throws -> DevelopmentStoreSnapshot {
        let value = try withLock(exclusive: false) { try loadLatest() }
        return Self.developmentSnapshot(value)
    }

    private func persist(_ value: VaultSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let plaintext = try encoder.encode(value)
        let box = try AES.GCM.seal(
            plaintext,
            using: key,
            authenticating: Self.authenticatedData
        )
        guard let combined = box.combined else { throw VaultStoreError.corruptPayload }
        try combined.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private func update(_ change: (inout VaultSnapshot) throws -> Void) throws {
        try withLock(exclusive: true) {
            var candidate = try loadLatest()
            try change(&candidate)
            try persist(candidate)
            snapshot = candidate
        }
    }

    private func synchronize() throws {
        snapshot = try withLock(exclusive: false) { try loadLatest() }
    }

    private func loadLatest() throws -> VaultSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return VaultSnapshot() }
        return try Self.read(fileURL: fileURL, key: key)
    }

    private func withLock<T>(exclusive: Bool, _ body: () throws -> T) throws -> T {
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw VaultStoreError.lockingFailed(errno) }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, exclusive ? LOCK_EX : LOCK_SH) == 0 else {
            throw VaultStoreError.lockingFailed(errno)
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }

    private static func developmentSnapshot(_ value: VaultSnapshot) -> DevelopmentStoreSnapshot {
        DevelopmentStoreSnapshot(
            captures: value.captures.values.sorted(by: captureOrder),
            proposals: value.proposals.values.sorted {
                $0.captureID.uuidString < $1.captureID.uuidString
            },
            intentions: value.intentions.values.sorted(by: intentionOrder)
        )
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

    private static func focusSessionOrder(_ lhs: FocusSession, _ rhs: FocusSession) -> Bool {
        if lhs.startedAt == rhs.startedAt { return lhs.id.uuidString < rhs.id.uuidString }
        return lhs.startedAt < rhs.startedAt
    }

    private static func resurfacingRuleOrder(
        _ lhs: ResurfacingRule,
        _ rhs: ResurfacingRule
    ) -> Bool {
        if lhs.createdAt == rhs.createdAt {
            return lhs.intentionID.uuidString < rhs.intentionID.uuidString
        }
        return lhs.createdAt < rhs.createdAt
    }

    private static func suggestionEventOrder(
        _ lhs: SuggestionEvent,
        _ rhs: SuggestionEvent
    ) -> Bool {
        if lhs.occurredAt == rhs.occurredAt { return lhs.id.uuidString < rhs.id.uuidString }
        return lhs.occurredAt < rhs.occurredAt
    }

    private static func validateCurrentFocus(
        _ focusSession: FocusSession,
        in snapshot: VaultSnapshot
    ) throws {
        guard focusSession.state == .active || focusSession.state == .paused else { return }
        if let current = snapshot.focusSessions.values.first(where: {
            ($0.state == .active || $0.state == .paused) && $0.id != focusSession.id
        }) {
            throw ThoughtRepositoryFocusError.currentFocusExists(current.intentionID)
        }
    }
}
