import Foundation
import Testing
@testable import ADHDCore

@Test func recallDocumentSourceProjectsEveryStoredEvidenceKindAndFinishedIntentions() async throws {
    let repository = RecallRepository()
    let capture = try RawCapture(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        createdAt: Date(timeIntervalSince1970: 1),
        text: "Discuss the release with Mira"
    )
    var finished = Intention(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        sourceCaptureID: capture.id,
        desiredOutcome: "Release decision recorded",
        nextAction: "Open the rollout notes",
        state: .active,
        createdAt: Date(timeIntervalSince1970: 2),
        returnPacket: nil
    )
    try finished.interrupt(with: ReturnPacket(
        capturedAt: Date(timeIntervalSince1970: 3),
        justCompleted: "Compared both rollout plans",
        nextAction: "Exact restart action",
        blocker: "Waiting for Mira",
        references: ["notes://release"]
    ))
    try finished.transition(to: .closed)
    let released = Intention(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        sourceCaptureID: capture.id,
        desiredOutcome: "Old released idea",
        nextAction: "No action",
        state: .released,
        createdAt: Date(timeIntervalSince1970: 4),
        returnPacket: nil
    )
    let correction = try TranscriptionCorrection(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        recognized: "call mirror", corrected: "Call Mira",
        createdAt: Date(timeIntervalSince1970: 5)
    )
    await repository.seed(captures: [capture], intentions: [finished, released], corrections: [correction])

    let documents = try await RecallDocumentSource(repository: repository).documents()

    #expect(Set(documents.map(\.evidenceID.kind)) == [.capture, .intention, .returnPacket, .correction])
    #expect(documents.count == 5)
    #expect(documents.contains { $0.text.contains("Exact restart action") })
    #expect(documents.contains { $0.text.contains("Old released idea") })
    #expect(documents.contains { $0.title == "Voice correction" && $0.text.contains("Call Mira") })
    #expect(documents.map(\.occurredAt) == documents.map(\.occurredAt).sorted())
}

private actor RecallRepository: ThoughtRepository {
    private var captureValues: [RawCapture] = []
    private var intentionValues: [Intention] = []
    private var correctionValues: [TranscriptionCorrection] = []

    func seed(
        captures: [RawCapture],
        intentions: [Intention],
        corrections: [TranscriptionCorrection]
    ) {
        captureValues = captures
        intentionValues = intentions
        correctionValues = corrections
    }

    func allCaptures() async throws -> [RawCapture] { captureValues }
    func allIntentions() async throws -> [Intention] { intentionValues }
    func transcriptionCorrections() async throws -> [TranscriptionCorrection] { correctionValues }
    func save(capture: RawCapture) async throws {}
    func save(proposal: ClarificationProposal) async throws {}
    func save(intention: Intention) async throws {}
    func captures(disposition: Disposition) async throws -> [RawCapture] { [] }
    func intention(id: UUID) async throws -> Intention? { nil }
    func openIntentions() async throws -> [Intention] { [] }
    func proposal(captureID: UUID) async throws -> ClarificationProposal? { nil }
}
