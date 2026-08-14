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
}

public protocol ClarificationProvider: Sendable {
    func propose(for capture: RawCapture) async throws -> ClarificationProposal
}
