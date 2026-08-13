import Foundation

public protocol ThoughtRepository: Sendable {
    func save(capture: RawCapture) async throws
    func save(intention: Intention) async throws
    func intention(id: UUID) async throws -> Intention?
    func openIntentions() async throws -> [Intention]
}

public protocol ClarificationProvider: Sendable {
    func propose(for capture: RawCapture) async throws -> ClarificationProposal
}
