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

@Test func recallRanksExactPhraseAndExposesLexicalContributions() async throws {
    let repository = RecallRepository()
    let exact = try RawCapture(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
        createdAt: Date(timeIntervalSince1970: 10),
        text: "The exact restart action is open the rollout notes"
    )
    let partial = try RawCapture(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
        createdAt: Date(timeIntervalSince1970: 20),
        text: "Restart after reviewing another action"
    )
    await repository.seed(captures: [partial, exact], intentions: [], corrections: [])
    let loop = RecallLoop(
        source: RecallDocumentSource(repository: repository),
        indexStore: MemoryRecallIndexStore(),
        embeddingProvider: FailingEmbeddingProvider()
    )

    let result = try await loop.retrieve(RecallQuery(text: "EXACT restart action"))

    #expect(result.hits.first?.evidenceID.id == exact.id)
    #expect(result.hits.first?.contributions.contains { $0.kind == .exactPhrase } == true)
    #expect(result.hits.first?.contributions.contains { $0.kind == .tokenCoverage } == true)
    #expect(result.hits.count == 2)
}

@Test func recallAddsSemanticEvidenceAndKeepsExactSearchWhenEmbeddingFails() async throws {
    let repository = RecallRepository()
    let semantic = try RawCapture(
        id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
        createdAt: Date(timeIntervalSince1970: 10),
        text: "Release conversation with Mira"
    )
    await repository.seed(captures: [semantic], intentions: [], corrections: [])
    let semanticLoop = RecallLoop(
        source: RecallDocumentSource(repository: repository),
        indexStore: MemoryRecallIndexStore(),
        embeddingProvider: FixtureEmbeddingProvider()
    )

    let semanticResult = try await semanticLoop.retrieve(RecallQuery(text: "launch discussion"))
    #expect(semanticResult.hits.first?.evidenceID.id == semantic.id)
    #expect(semanticResult.hits.first?.contributions.contains {
        $0.kind == .semanticSimilarity
    } == true)

    let fallback = RecallLoop(
        source: RecallDocumentSource(repository: repository),
        indexStore: MemoryRecallIndexStore(),
        embeddingProvider: FailingEmbeddingProvider()
    )
    let exactResult = try await fallback.retrieve(RecallQuery(text: "Mira"))
    #expect(exactResult.hits.first?.evidenceID.id == semantic.id)
    await #expect(throws: RecallError.emptyQuery) {
        _ = try await fallback.retrieve(RecallQuery(text: "  "))
    }
}

private actor MemoryRecallIndexStore: RecallIndexStore {
    private var value: RecallIndexSnapshot?
    func load() async throws -> RecallIndexSnapshot? { value }
    func save(_ snapshot: RecallIndexSnapshot) async throws { value = snapshot }
    func discard() async throws { value = nil }
}

private struct FixtureEmbeddingProvider: EmbeddingProvider {
    var identifier: String { get async { "fixture-v1" } }
    func vectors(for texts: [String]) async throws -> [[Double]] {
        texts.map { text in
            let normalized = text.lowercased()
            if normalized.contains("launch discussion") || normalized.contains("release conversation") {
                return [1, 0]
            }
            return [0, 1]
        }
    }
}

private struct FailingEmbeddingProvider: EmbeddingProvider {
    var identifier: String { get async { "failure-v1" } }
    func vectors(for texts: [String]) async throws -> [[Double]] {
        throw RecallError.embeddingUnavailable
    }
}

@Test func recallEvaluationReportsTopFiveAndExactNearestRankP95() {
    let id = RecallEvidenceID(kind: .capture, id: UUID())
    let hit = RecallHit(
        evidenceID: id, title: "Capture", excerpt: "Evidence",
        occurredAt: .distantPast, score: 1,
        contributions: [RecallContribution(kind: .exactPhrase, value: 1)]
    )
    let cases = [
        RecallEvaluationCase(query: "one", expectedEvidence: [id], exact: true),
        RecallEvaluationCase(query: "two", expectedEvidence: [id], exact: false),
    ]
    let report = RecallEvaluationReport(
        cases: cases,
        results: [RecallResult(query: "one", hits: [hit]), RecallResult(query: "two", hits: [])],
        latenciesMilliseconds: [12, 99]
    )

    #expect(report.caseCount == 2)
    #expect(report.topFiveHitRate == 0.5)
    #expect(report.exactSearchP95Milliseconds == 12)
    let empty = RecallEvaluationReport(cases: [], results: [], latenciesMilliseconds: [])
    #expect(empty.topFiveHitRate == nil)
    #expect(empty.exactSearchP95Milliseconds == nil)
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
