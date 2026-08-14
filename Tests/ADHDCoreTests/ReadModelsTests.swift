import Foundation
import Testing
@testable import ADHDCore

private actor ReadRepository: ThoughtRepository {
    var storedCaptures: [UUID: RawCapture] = [:]
    var storedProposals: [UUID: ClarificationProposal] = [:]
    var storedIntentions: [UUID: Intention] = [:]

    func save(capture: RawCapture) async throws { storedCaptures[capture.id] = capture }
    func save(proposal: ClarificationProposal) async throws {
        storedProposals[proposal.captureID] = proposal
    }
    func save(intention: Intention) async throws { storedIntentions[intention.id] = intention }
    func proposal(captureID: UUID) async throws -> ClarificationProposal? {
        storedProposals[captureID]
    }
    func captures(disposition: Disposition) async throws -> [RawCapture] {
        storedCaptures.values.filter { storedProposals[$0.id]?.disposition == disposition }
    }
    func unclarifiedCaptures() async throws -> [RawCapture] {
        storedCaptures.values.filter { storedProposals[$0.id] == nil }
    }
    func intention(id: UUID) async throws -> Intention? { storedIntentions[id] }
    func openIntentions() async throws -> [Intention] {
        storedIntentions.values.filter { $0.state != .closed && $0.state != .released }
    }
}

@Test func nowPrefersAnActiveIntention() async throws {
    let repository = ReadRepository()
    let captureID = UUID()
    let olderOpen = Intention(
        id: UUID(), sourceCaptureID: captureID, desiredOutcome: "Older",
        nextAction: "Wait", state: .open, createdAt: Date(timeIntervalSince1970: 1),
        returnPacket: nil
    )
    let active = Intention(
        id: UUID(), sourceCaptureID: captureID, desiredOutcome: "Current",
        nextAction: "Begin", state: .active, createdAt: Date(timeIntervalSince1970: 2),
        returnPacket: nil
    )
    try await repository.save(intention: olderOpen)
    try await repository.save(intention: active)

    let item = try await ThoughtReadModels(repository: repository).now()

    #expect(item?.intentionID == active.id)
    #expect(item?.nextAction == "Begin")
}

@Test func laterIncludesSafeNonActionDispositionsAndExcludesRelease() async throws {
    let repository = ReadRepository()
    let models = ThoughtReadModels(repository: repository)
    let dispositions: [Disposition] = [.later, .memory, .unclear, .release]

    let pending = try RawCapture(
        createdAt: Date(timeIntervalSince1970: -1),
        text: "pending clarification"
    )
    try await repository.save(capture: pending)

    for (index, disposition) in dispositions.enumerated() {
        let capture = try RawCapture(
            createdAt: Date(timeIntervalSince1970: Double(index)),
            text: disposition.rawValue
        )
        let proposal = try ClarificationProposal(
            captureID: capture.id, disposition: disposition, desiredOutcome: nil,
            nextAction: nil, confidence: 1
        )
        try await repository.save(capture: capture)
        try await repository.save(proposal: proposal)
    }

    let items = try await models.later()

    #expect(items.map(\.disposition) == [.unclear, .later, .memory, .unclear])
    #expect(items.map(\.text) == ["pending clarification", "later", "memory", "unclear"])
}
