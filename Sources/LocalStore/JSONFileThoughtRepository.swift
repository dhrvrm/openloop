import ADHDCore
import Foundation

private struct Snapshot: Codable {
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
    }
}

public enum JSONFileThoughtRepositoryError: Error, Equatable {
    case corruptSnapshot
    case storeMigrated
}

public actor JSONFileThoughtRepository: ThoughtRepository {
    private let fileURL: URL
    private let storeLock: DevelopmentStoreLock
    private var snapshot: Snapshot

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        fileURL = directory.appendingPathComponent("thought-loop.json")
        storeLock = try DevelopmentStoreLock(directory: directory)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            do {
                snapshot = try JSONDecoder().decode(
                    Snapshot.self,
                    from: data
                )
            } catch {
                throw JSONFileThoughtRepositoryError.corruptSnapshot
            }
        } else {
            snapshot = Snapshot()
        }
    }

    public func save(capture: RawCapture) async throws {
        try update { $0.captures[capture.id] = capture }
    }

    public func capture(id: UUID) async throws -> RawCapture? {
        snapshot.captures[id]
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
        snapshot.clarificationCorrections.values
            .filter { captureID == nil || $0.captureID == captureID }
            .sorted(by: Self.clarificationCorrectionOrder)
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
        snapshot.proposals[captureID]
    }

    public func captures(disposition: Disposition) async throws -> [RawCapture] {
        snapshot.captures.values
            .filter { snapshot.proposals[$0.id]?.disposition == disposition }
            .sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.createdAt < $1.createdAt
            }
    }

    public func unclarifiedCaptures() async throws -> [RawCapture] {
        snapshot.captures.values
            .filter { snapshot.proposals[$0.id] == nil }
            .sorted(by: Self.captureOrder)
    }

    public func capturesRequiringClarification() async throws -> [RawCapture] {
        let intentionSources = Set(snapshot.intentions.values.map(\.sourceCaptureID))
        return snapshot.captures.values
            .filter { capture in
                guard let proposal = snapshot.proposals[capture.id] else { return true }
                return proposal.disposition == .action && intentionSources.contains(capture.id) == false
            }
            .sorted(by: Self.captureOrder)
    }

    public func intention(id: UUID) async throws -> Intention? {
        snapshot.intentions[id]
    }

    public func openIntentions() async throws -> [Intention] {
        snapshot.intentions.values
            .filter { $0.state != .closed && $0.state != .released }
            .sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.createdAt < $1.createdAt
            }
    }

    public func focusSession(id: UUID) async throws -> FocusSession? {
        snapshot.focusSessions[id]
    }

    public func focusSessions() async throws -> [FocusSession] {
        snapshot.focusSessions.values.sorted(by: Self.focusSessionOrder)
    }

    public func save(resurfacingRule: ResurfacingRule) async throws {
        try update { $0.resurfacingRules[resurfacingRule.intentionID] = resurfacingRule }
    }

    public func deleteResurfacingRule(intentionID: UUID) async throws {
        try update { $0.resurfacingRules[intentionID] = nil }
    }

    public func resurfacingRules() async throws -> [ResurfacingRule] {
        snapshot.resurfacingRules.values.sorted(by: Self.resurfacingRuleOrder)
    }

    public func append(suggestionEvent: SuggestionEvent) async throws {
        try update { $0.suggestionEvents[suggestionEvent.id] = suggestionEvent }
    }

    public func suggestionEvents() async throws -> [SuggestionEvent] {
        snapshot.suggestionEvents.values.sorted(by: Self.suggestionEventOrder)
    }

    public func save(transcriptionCorrection: TranscriptionCorrection) async throws {
        try update { $0.transcriptionCorrections[transcriptionCorrection.id] = transcriptionCorrection }
    }

    public func transcriptionCorrections() async throws -> [TranscriptionCorrection] {
        snapshot.transcriptionCorrections.values.sorted(by: Self.transcriptionCorrectionOrder)
    }

    public func save(memoryRecords: [MemoryRecord]) async throws {
        try update { snapshot in
            snapshot.memoryRecords = Dictionary(
                uniqueKeysWithValues: memoryRecords.map { ($0.id, $0) }
            )
        }
    }

    public func memoryRecords() async throws -> [MemoryRecord] {
        snapshot.memoryRecords.values.sorted(by: Self.memoryRecordOrder)
    }

    public func save(contextTrailSettings: ContextTrailSettings) async throws {
        try update { $0.contextTrailSettings = contextTrailSettings }
    }

    public func contextTrailSettings() async throws -> ContextTrailSettings {
        snapshot.contextTrailSettings
    }

    public func append(contextTrailEvent: ContextTrailEvent) async throws {
        try update { $0.contextTrailEvents[contextTrailEvent.id] = contextTrailEvent }
    }

    public func contextTrailEvents() async throws -> [ContextTrailEvent] {
        snapshot.contextTrailEvents.values.sorted(by: ContextTrailPolicy.eventComesBefore)
    }

    public func replace(contextTrailEvents: [ContextTrailEvent]) async throws {
        try update { snapshot in
            snapshot.contextTrailEvents = Dictionary(
                uniqueKeysWithValues: contextTrailEvents.map { ($0.id, $0) }
            )
        }
    }

    public func allCaptures() async throws -> [RawCapture] {
        snapshot.captures.values.sorted(by: Self.captureOrder)
    }

    public func allIntentions() async throws -> [Intention] {
        snapshot.intentions.values.sorted(by: Self.intentionOrder)
    }

    func snapshotCaptures() -> [RawCapture] {
        snapshot.captures.values.sorted(by: Self.captureOrder)
    }

    func snapshotProposals() -> [ClarificationProposal] {
        snapshot.proposals.values.sorted { $0.captureID.uuidString < $1.captureID.uuidString }
    }

    func snapshotClarificationCorrections() -> [ClarificationCorrection] {
        snapshot.clarificationCorrections.values.sorted(by: Self.clarificationCorrectionOrder)
    }

    func snapshotIntentions() -> [Intention] {
        snapshot.intentions.values.sorted(by: Self.intentionOrder)
    }

    private func update(_ change: (inout Snapshot) throws -> Void) throws {
        try storeLock.lockExclusive()
        defer { storeLock.unlock() }
        let marker = fileURL.deletingLastPathComponent()
            .appendingPathComponent("thought-loop.migrated")
        guard FileManager.default.fileExists(atPath: marker.path) == false else {
            throw JSONFileThoughtRepositoryError.storeMigrated
        }
        var candidate = try loadLatest()
        try change(&candidate)
        let data = try JSONEncoder().encode(candidate)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        snapshot = candidate
    }

    private func loadLatest() throws -> Snapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return Snapshot() }
        do {
            return try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: fileURL))
        } catch {
            throw JSONFileThoughtRepositoryError.corruptSnapshot
        }
    }

    private static func validateCurrentFocus(
        _ focusSession: FocusSession,
        in snapshot: Snapshot
    ) throws {
        guard focusSession.state == .active || focusSession.state == .paused else { return }
        if let current = snapshot.focusSessions.values.first(where: {
            ($0.state == .active || $0.state == .paused) && $0.id != focusSession.id
        }) {
            throw ThoughtRepositoryFocusError.currentFocusExists(current.intentionID)
        }
    }

    private static func clarificationCorrectionOrder(
        _ lhs: ClarificationCorrection,
        _ rhs: ClarificationCorrection
    ) -> Bool {
        if lhs.reviewedAt == rhs.reviewedAt { return lhs.id.uuidString < rhs.id.uuidString }
        return lhs.reviewedAt < rhs.reviewedAt
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
}
