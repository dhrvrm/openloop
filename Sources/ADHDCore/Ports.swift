import Foundation

public protocol ThoughtRepository: Sendable {
    func save(capture: RawCapture) async throws
    func save(proposal: ClarificationProposal) async throws
    func save(intention: Intention) async throws
    func proposal(captureID: UUID) async throws -> ClarificationProposal?
    func captures(disposition: Disposition) async throws -> [RawCapture]
    func intention(id: UUID) async throws -> Intention?
    func openIntentions() async throws -> [Intention]
}

public protocol ClarificationProvider: Sendable {
    func propose(for capture: RawCapture) async throws -> ClarificationProposal
}
