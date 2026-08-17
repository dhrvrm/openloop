import Foundation

public protocol ThoughtRepository: Sendable {
    func save(capture: RawCapture) async throws
    func save(proposal: ClarificationProposal) async throws
    func save(proposal: ClarificationProposal, intention: Intention?) async throws
    func save(intention: Intention) async throws
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
    func save(memoryRecords: [MemoryRecord]) async throws
    func memoryRecords() async throws -> [MemoryRecord]
    func save(contextTrailSettings: ContextTrailSettings) async throws
    func contextTrailSettings() async throws -> ContextTrailSettings
    func append(contextTrailEvent: ContextTrailEvent) async throws
    func contextTrailEvents() async throws -> [ContextTrailEvent]
    func replace(contextTrailEvents: [ContextTrailEvent]) async throws
    func allCaptures() async throws -> [RawCapture]
    func allIntentions() async throws -> [Intention]
}

public enum ThoughtRepositoryCompatibilityError: Error, Equatable {
    case focusSessionsUnsupported
    case resurfacingUnsupported
    case voiceLearningUnsupported
    case workingMemoryUnsupported
    case contextTrailUnsupported
}

public enum ThoughtRepositoryFocusError: Error, Equatable {
    case currentFocusExists(UUID)
}

public extension ThoughtRepository {
    func save(proposal: ClarificationProposal, intention: Intention?) async throws {
        try await save(proposal: proposal)
        if let intention { try await save(intention: intention) }
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
}

public protocol ClarificationProvider: Sendable {
    func propose(for capture: RawCapture) async throws -> ClarificationProposal
}
