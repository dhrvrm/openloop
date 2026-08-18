import ADHDCore
import CryptoKit
import Darwin
import Foundation
import LocalStore

private struct VaultSnapshot: Codable {
    var captures: [UUID: RawCapture] = [:]
    var proposals: [UUID: ClarificationProposal] = [:]
    var clarificationCorrections: [UUID: ClarificationCorrection] = [:]
    var intentions: [UUID: Intention] = [:]
    var focusSessions: [UUID: FocusSession] = [:]
    var resurfacingRules: [UUID: ResurfacingRule] = [:]
    var suggestionEvents: [UUID: SuggestionEvent] = [:]
    var transcriptionCorrections: [UUID: TranscriptionCorrection] = [:]
    var memoryRecords: [UUID: MemoryRecord] = [:]
    var contextTrailSettings = ContextTrailSettings()
    var contextTrailEvents: [UUID: ContextTrailEvent] = [:]
    var retentionPolicy = PrivacyRetentionPolicy.keepForever

    private enum CodingKeys: String, CodingKey {
        case captures
        case proposals
        case clarificationCorrections
        case intentions
        case focusSessions
        case resurfacingRules
        case suggestionEvents
        case transcriptionCorrections
        case memoryRecords
        case contextTrailSettings
        case contextTrailEvents
        case retentionPolicy
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        captures = try container.decode([UUID: RawCapture].self, forKey: .captures)
        proposals = try container.decodeIfPresent(
            [UUID: ClarificationProposal].self,
            forKey: .proposals
        ) ?? [:]
        clarificationCorrections = try container.decodeIfPresent(
            [UUID: ClarificationCorrection].self,
            forKey: .clarificationCorrections
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
        transcriptionCorrections = try container.decodeIfPresent(
            [UUID: TranscriptionCorrection].self,
            forKey: .transcriptionCorrections
        ) ?? [:]
        memoryRecords = try container.decodeIfPresent(
            [UUID: MemoryRecord].self,
            forKey: .memoryRecords
        ) ?? [:]
        contextTrailSettings = try container.decodeIfPresent(
            ContextTrailSettings.self,
            forKey: .contextTrailSettings
        ) ?? ContextTrailSettings()
        contextTrailEvents = try container.decodeIfPresent(
            [UUID: ContextTrailEvent].self,
            forKey: .contextTrailEvents
        ) ?? [:]
        retentionPolicy = try container.decodeIfPresent(
            PrivacyRetentionPolicy.self,
            forKey: .retentionPolicy
        ) ?? .keepForever
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

    public func capture(id: UUID) async throws -> RawCapture? {
        try synchronize()
        return snapshot.captures[id]
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

    public func apply(
        clarificationCorrection: ClarificationCorrection,
        intention: Intention?
    ) async throws {
        try update {
            $0.proposals[clarificationCorrection.captureID] = clarificationCorrection.proposal
            $0.clarificationCorrections[clarificationCorrection.id] = clarificationCorrection
            if let intention { $0.intentions[intention.id] = intention }
        }
    }

    public func clarificationCorrections(captureID: UUID?) async throws
        -> [ClarificationCorrection] {
        try synchronize()
        return snapshot.clarificationCorrections.values
            .filter { captureID == nil || $0.captureID == captureID }
            .sorted(by: Self.clarificationCorrectionOrder)
    }

    public func save(intention: Intention) async throws {
        try update { $0.intentions[intention.id] = intention }
    }

    public func save(intentions: [Intention]) async throws {
        try update { snapshot in
            for intention in intentions { snapshot.intentions[intention.id] = intention }
        }
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

    public func save(transcriptionCorrection: TranscriptionCorrection) async throws {
        try update { $0.transcriptionCorrections[transcriptionCorrection.id] = transcriptionCorrection }
    }

    public func transcriptionCorrections() async throws -> [TranscriptionCorrection] {
        try synchronize()
        return snapshot.transcriptionCorrections.values.sorted(
            by: Self.transcriptionCorrectionOrder
        )
    }

    public func save(memoryRecords: [MemoryRecord]) async throws {
        try update { snapshot in
            snapshot.memoryRecords = Dictionary(
                uniqueKeysWithValues: memoryRecords.map { ($0.id, $0) }
            )
        }
    }

    public func memoryRecords() async throws -> [MemoryRecord] {
        try synchronize()
        return snapshot.memoryRecords.values.sorted(by: Self.memoryRecordOrder)
    }

    public func save(contextTrailSettings: ContextTrailSettings) async throws {
        try update { $0.contextTrailSettings = contextTrailSettings }
    }

    public func contextTrailSettings() async throws -> ContextTrailSettings {
        try synchronize()
        return snapshot.contextTrailSettings
    }

    public func append(contextTrailEvent: ContextTrailEvent) async throws {
        try update { $0.contextTrailEvents[contextTrailEvent.id] = contextTrailEvent }
    }

    public func contextTrailEvents() async throws -> [ContextTrailEvent] {
        try synchronize()
        return snapshot.contextTrailEvents.values.sorted(by: ContextTrailPolicy.eventComesBefore)
    }

    public func replace(contextTrailEvents: [ContextTrailEvent]) async throws {
        try update { snapshot in
            snapshot.contextTrailEvents = Dictionary(
                uniqueKeysWithValues: contextTrailEvents.map { ($0.id, $0) }
            )
        }
    }

    public func allCaptures() async throws -> [RawCapture] {
        try synchronize()
        return snapshot.captures.values.sorted(by: Self.captureOrder)
    }

    public func allIntentions() async throws -> [Intention] {
        try synchronize()
        return snapshot.intentions.values.sorted(by: Self.intentionOrder)
    }

    public func privacySummary() async throws -> PrivacyDataSummary {
        try synchronize()
        let open = snapshot.intentions.values.filter(Self.isOpen).count
        return PrivacyDataSummary(
            captureCount: snapshot.captures.count,
            openIntentionCount: open,
            completedIntentionCount: snapshot.intentions.count - open,
            memoryCount: snapshot.memoryRecords.count,
            contextEventCount: snapshot.contextTrailEvents.count,
            encryptedBytes: Self.fileSize(fileURL)
        )
    }

    public func retentionPolicy() async throws -> PrivacyRetentionPolicy {
        try synchronize()
        return snapshot.retentionPolicy
    }

    public func applyRetention(
        _ policy: PrivacyRetentionPolicy,
        at date: Date
    ) async throws -> RetentionResult {
        var result = RetentionResult(removedCaptures: 0, removedIntentions: 0)
        try update { snapshot in
            snapshot.retentionPolicy = policy
            result = Self.apply(policy: policy, at: date, to: &snapshot)
        }
        return result
    }

    public func resetAllData() async throws {
        try update { $0 = VaultSnapshot() }
    }

    public func exportEncryptedBackup(to destination: URL) throws {
        try update { _ in }
        let payload = try withLock(exclusive: false) { try Data(contentsOf: fileURL) }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try payload.write(to: destination, options: [.atomic, .completeFileProtection])
    }

    public func empty() throws -> Bool {
        try synchronize()
        return snapshot.captures.isEmpty
            && snapshot.proposals.isEmpty
            && snapshot.clarificationCorrections.isEmpty
            && snapshot.intentions.isEmpty
            && snapshot.focusSessions.isEmpty
            && snapshot.resurfacingRules.isEmpty
            && snapshot.suggestionEvents.isEmpty
            && snapshot.transcriptionCorrections.isEmpty
            && snapshot.memoryRecords.isEmpty
            && snapshot.contextTrailSettings == ContextTrailSettings()
            && snapshot.contextTrailEvents.isEmpty
            && snapshot.retentionPolicy == .keepForever
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
              Set(value.clarificationCorrections.map(\.id)).count
                == value.clarificationCorrections.count,
              Set(value.intentions.map(\.id)).count == value.intentions.count else {
            throw VaultStoreError.duplicateMigrationID
        }
        guard value.proposals.allSatisfy({ captureIDs.contains($0.captureID) }),
              value.clarificationCorrections.allSatisfy({ captureIDs.contains($0.captureID) }),
              value.intentions.allSatisfy({ captureIDs.contains($0.sourceCaptureID) }) else {
            throw VaultStoreError.invalidMigrationReference
        }
        try update { candidate in
            guard candidate.captures.isEmpty,
                  candidate.proposals.isEmpty,
                  candidate.clarificationCorrections.isEmpty,
                  candidate.intentions.isEmpty,
                  candidate.focusSessions.isEmpty,
                  candidate.resurfacingRules.isEmpty,
                  candidate.suggestionEvents.isEmpty,
                  candidate.transcriptionCorrections.isEmpty,
                  candidate.memoryRecords.isEmpty,
                  candidate.contextTrailSettings == ContextTrailSettings(),
                  candidate.contextTrailEvents.isEmpty,
                  candidate.retentionPolicy == .keepForever else {
                throw VaultStoreError.vaultNotEmpty
            }
            candidate.captures = Dictionary(uniqueKeysWithValues: value.captures.map { ($0.id, $0) })
            candidate.proposals = Dictionary(uniqueKeysWithValues: value.proposals.map { ($0.captureID, $0) })
            candidate.clarificationCorrections = Dictionary(
                uniqueKeysWithValues: value.clarificationCorrections.map { ($0.id, $0) }
            )
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
            clarificationCorrections: value.clarificationCorrections.values.sorted(
                by: clarificationCorrectionOrder
            ),
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

    private static func clarificationCorrectionOrder(
        _ lhs: ClarificationCorrection,
        _ rhs: ClarificationCorrection
    ) -> Bool {
        if lhs.reviewedAt == rhs.reviewedAt { return lhs.id.uuidString < rhs.id.uuidString }
        return lhs.reviewedAt < rhs.reviewedAt
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

    private static func transcriptionCorrectionOrder(
        _ lhs: TranscriptionCorrection,
        _ rhs: TranscriptionCorrection
    ) -> Bool {
        if lhs.createdAt == rhs.createdAt { return lhs.id.uuidString < rhs.id.uuidString }
        return lhs.createdAt < rhs.createdAt
    }

    private static func memoryRecordOrder(_ lhs: MemoryRecord, _ rhs: MemoryRecord) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func apply(
        policy: PrivacyRetentionPolicy,
        at date: Date,
        to snapshot: inout VaultSnapshot
    ) -> RetentionResult {
        guard let age = policy.age else { return RetentionResult(removedCaptures: 0, removedIntentions: 0) }
        let cutoff = date.addingTimeInterval(-age)
        let removableCaptureIDs = Set(snapshot.captures.values.compactMap { capture -> UUID? in
            guard capture.createdAt < cutoff else { return nil }
            guard let intention = snapshot.intentions.values.first(where: { $0.sourceCaptureID == capture.id }) else {
                return capture.id
            }
            return Self.isOpen(intention) ? nil : capture.id
        })
        let removableIntentionIDs = Set(snapshot.intentions.values.compactMap {
            removableCaptureIDs.contains($0.sourceCaptureID) ? $0.id : nil
        })
        let removableSessionIDs = Set(snapshot.focusSessions.values.compactMap {
            removableIntentionIDs.contains($0.intentionID) ? $0.id : nil
        })
        let removableCorrectionIDs = Set(snapshot.transcriptionCorrections.values.compactMap {
            $0.createdAt < cutoff ? $0.id : nil
        })

        snapshot.captures = snapshot.captures.filter { !removableCaptureIDs.contains($0.key) }
        snapshot.proposals = snapshot.proposals.filter { !removableCaptureIDs.contains($0.key) }
        snapshot.clarificationCorrections = snapshot.clarificationCorrections.filter {
            !removableCaptureIDs.contains($0.value.captureID)
        }
        snapshot.intentions = snapshot.intentions.filter { !removableIntentionIDs.contains($0.key) }
        snapshot.focusSessions = snapshot.focusSessions.filter { !removableSessionIDs.contains($0.key) }
        snapshot.resurfacingRules = snapshot.resurfacingRules.filter {
            !removableIntentionIDs.contains($0.key)
        }
        snapshot.suggestionEvents = snapshot.suggestionEvents.filter {
            !removableIntentionIDs.contains($0.value.intentionID)
        }
        snapshot.contextTrailEvents = snapshot.contextTrailEvents.filter {
            !removableSessionIDs.contains($0.value.focusSessionID) && $0.value.observedAt >= cutoff
        }
        snapshot.transcriptionCorrections = snapshot.transcriptionCorrections.filter {
            !removableCorrectionIDs.contains($0.key)
        }
        snapshot.memoryRecords = snapshot.memoryRecords.compactMapValues { record in
            Self.removingEvidence(
                in: record,
                captureIDs: removableCaptureIDs,
                intentionIDs: removableIntentionIDs,
                correctionIDs: removableCorrectionIDs,
                at: date
            )
        }
        return RetentionResult(
            removedCaptures: removableCaptureIDs.count,
            removedIntentions: removableIntentionIDs.count
        )
    }

    private static func removingEvidence(
        in record: MemoryRecord,
        captureIDs: Set<UUID>,
        intentionIDs: Set<UUID>,
        correctionIDs: Set<UUID>,
        at date: Date
    ) -> MemoryRecord? {
        var updated = record
        updated.evidence = record.evidence.filter { evidence in
            let removed = switch evidence.evidenceID.kind {
            case .capture: captureIDs.contains(evidence.evidenceID.id)
            case .intention, .returnPacket: intentionIDs.contains(evidence.evidenceID.id)
            case .correction: correctionIDs.contains(evidence.evidenceID.id)
            case .memory: false
            }
            return !removed
        }
        guard !updated.evidence.isEmpty else { return nil }
        if updated != record { updated.updatedAt = date }
        return updated
    }

    private static func isOpen(_ intention: Intention) -> Bool {
        intention.state == .open || intention.state == .active || intention.state == .interrupted
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
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
