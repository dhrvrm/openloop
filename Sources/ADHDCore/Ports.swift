import Foundation

public protocol ThoughtRepository: Sendable {
    func save(capture: RawCapture) async throws
    func capture(id: UUID) async throws -> RawCapture?
    func save(proposal: ClarificationProposal) async throws
    func save(proposal: ClarificationProposal, intention: Intention?) async throws
    func apply(
        clarificationCorrection: ClarificationCorrection,
        intention: Intention?
    ) async throws
    func clarificationCorrections(captureID: UUID?) async throws -> [ClarificationCorrection]
    func save(intention: Intention) async throws
    func save(intentions: [Intention]) async throws
    func unclarifiedCaptures() async throws -> [RawCapture]
    func capturesRequiringClarification() async throws -> [RawCapture]
    func proposal(captureID: UUID) async throws -> ClarificationProposal?
    func captures(disposition: Disposition) async throws -> [RawCapture]
    func intention(id: UUID) async throws -> Intention?
    func openIntentions() async throws -> [Intention]
    func save(focusSession: FocusSession) async throws
    func save(intention: Intention, focusSession: FocusSession) async throws
    func focusSession(id: UUID) async throws -> FocusSession?
    func focusSessions() async throws -> [FocusSession]
    func save(resurfacingRule: ResurfacingRule) async throws
    func deleteResurfacingRule(intentionID: UUID) async throws
    func resurfacingRules() async throws -> [ResurfacingRule]
    func append(suggestionEvent: SuggestionEvent) async throws
    func suggestionEvents() async throws -> [SuggestionEvent]
    func save(transcriptionCorrection: TranscriptionCorrection) async throws
    func transcriptionCorrections() async throws -> [TranscriptionCorrection]
    func save(voiceQualityCase: VoiceQualityCase) async throws
    func voiceQualityCases() async throws -> [VoiceQualityCase]
    func save(voiceQualityAttempt: VoiceQualityAttempt) async throws
    func voiceQualityAttempts(caseID: UUID?) async throws -> [VoiceQualityAttempt]
    func save(meetingTranscript: MeetingTranscript) async throws
    func meetingTranscripts() async throws -> [MeetingTranscript]
    func deleteMeetingTranscript(id: UUID) async throws
    func save(memoryRecords: [MemoryRecord]) async throws
    func memoryRecords() async throws -> [MemoryRecord]
    func save(contextTrailSettings: ContextTrailSettings) async throws
    func contextTrailSettings() async throws -> ContextTrailSettings
    func append(contextTrailEvent: ContextTrailEvent) async throws
    func contextTrailEvents() async throws -> [ContextTrailEvent]
    func replace(contextTrailEvents: [ContextTrailEvent]) async throws
    func allCaptures() async throws -> [RawCapture]
    func allIntentions() async throws -> [Intention]
    func privacySummary() async throws -> PrivacyDataSummary
    func retentionPolicy() async throws -> PrivacyRetentionPolicy
    func applyRetention(_ policy: PrivacyRetentionPolicy, at date: Date) async throws
        -> RetentionResult
    func resetAllData() async throws
}

public enum ThoughtRepositoryCompatibilityError: Error, Equatable {
    case focusSessionsUnsupported
    case resurfacingUnsupported
    case voiceLearningUnsupported
    case meetingTranscriptionUnsupported
    case workingMemoryUnsupported
    case contextTrailUnsupported
    case privacyUnsupported
}

public enum ThoughtRepositoryFocusError: Error, Equatable {
    case currentFocusExists(UUID)
}

public extension ThoughtRepository {
    func capture(id: UUID) async throws -> RawCapture? {
        try await allCaptures().first { $0.id == id }
    }

    func save(proposal: ClarificationProposal, intention: Intention?) async throws {
        try await save(proposal: proposal)
        if let intention { try await save(intention: intention) }
    }

    func apply(
        clarificationCorrection: ClarificationCorrection,
        intention: Intention?
    ) async throws {
        try await save(proposal: clarificationCorrection.proposal, intention: intention)
    }

    func clarificationCorrections(captureID: UUID? = nil) async throws
        -> [ClarificationCorrection] {
        []
    }

    func unclarifiedCaptures() async throws -> [RawCapture] { [] }

    func capturesRequiringClarification() async throws -> [RawCapture] {
        try await unclarifiedCaptures()
    }

    func save(focusSession: FocusSession) async throws {
        throw ThoughtRepositoryCompatibilityError.focusSessionsUnsupported
    }

    func save(intention: Intention, focusSession: FocusSession) async throws {
        throw ThoughtRepositoryCompatibilityError.focusSessionsUnsupported
    }

    func focusSession(id: UUID) async throws -> FocusSession? { nil }

    func focusSessions() async throws -> [FocusSession] { [] }

    func save(resurfacingRule: ResurfacingRule) async throws {
        throw ThoughtRepositoryCompatibilityError.resurfacingUnsupported
    }

    func deleteResurfacingRule(intentionID: UUID) async throws {
        throw ThoughtRepositoryCompatibilityError.resurfacingUnsupported
    }

    func resurfacingRules() async throws -> [ResurfacingRule] { [] }

    func append(suggestionEvent: SuggestionEvent) async throws {
        throw ThoughtRepositoryCompatibilityError.resurfacingUnsupported
    }

    func suggestionEvents() async throws -> [SuggestionEvent] { [] }

    func save(transcriptionCorrection: TranscriptionCorrection) async throws {
        throw ThoughtRepositoryCompatibilityError.voiceLearningUnsupported
    }

    func transcriptionCorrections() async throws -> [TranscriptionCorrection] { [] }

    func save(voiceQualityCase: VoiceQualityCase) async throws {
        throw ThoughtRepositoryCompatibilityError.voiceLearningUnsupported
    }

    func voiceQualityCases() async throws -> [VoiceQualityCase] { [] }

    func save(voiceQualityAttempt: VoiceQualityAttempt) async throws {
        throw ThoughtRepositoryCompatibilityError.voiceLearningUnsupported
    }

    func voiceQualityAttempts(caseID: UUID? = nil) async throws -> [VoiceQualityAttempt] { [] }

    func save(meetingTranscript: MeetingTranscript) async throws {
        throw ThoughtRepositoryCompatibilityError.meetingTranscriptionUnsupported
    }

    func meetingTranscripts() async throws -> [MeetingTranscript] { [] }

    func deleteMeetingTranscript(id: UUID) async throws {
        throw ThoughtRepositoryCompatibilityError.meetingTranscriptionUnsupported
    }

    func save(memoryRecords: [MemoryRecord]) async throws {
        throw ThoughtRepositoryCompatibilityError.workingMemoryUnsupported
    }

    func memoryRecords() async throws -> [MemoryRecord] { [] }

    func save(contextTrailSettings: ContextTrailSettings) async throws {
        throw ThoughtRepositoryCompatibilityError.contextTrailUnsupported
    }

    func contextTrailSettings() async throws -> ContextTrailSettings { ContextTrailSettings() }

    func append(contextTrailEvent: ContextTrailEvent) async throws {
        throw ThoughtRepositoryCompatibilityError.contextTrailUnsupported
    }

    func contextTrailEvents() async throws -> [ContextTrailEvent] { [] }

    func replace(contextTrailEvents: [ContextTrailEvent]) async throws {
        throw ThoughtRepositoryCompatibilityError.contextTrailUnsupported
    }

    func allCaptures() async throws -> [RawCapture] { [] }

    func allIntentions() async throws -> [Intention] { [] }

    func save(intentions: [Intention]) async throws {
        for intention in intentions { try await save(intention: intention) }
    }

    func privacySummary() async throws -> PrivacyDataSummary { .empty }

    func retentionPolicy() async throws -> PrivacyRetentionPolicy { .keepForever }

    func applyRetention(
        _ policy: PrivacyRetentionPolicy,
        at date: Date
    ) async throws -> RetentionResult {
        RetentionResult(removedCaptures: 0, removedIntentions: 0)
    }

    func resetAllData() async throws {
        throw ThoughtRepositoryCompatibilityError.privacyUnsupported
    }
}

public protocol ClarificationProvider: Sendable {
    func propose(for capture: RawCapture) async throws -> ClarificationProposal
}
