import Foundation
import Testing
@testable import ADHDCore

@Test func deterministicMemoryExtractionAcceptsOnlyExplicitEvidenceMarkers() async throws {
    let documents = [
        memoryDocument(id: 1, text: "decision: Ship the smaller release"),
        memoryDocument(id: 2, text: "commitment: Send Mira the notes"),
        memoryDocument(id: 3, text: "prefer: Quiet mornings for review"),
        memoryDocument(id: 4, text: "question: Which rollout metric matters?"),
        memoryDocument(id: 5, text: "remember: The staging key expires Friday"),
        memoryDocument(id: 6, text: "This ordinary capture stays evidence only"),
        memoryDocument(id: 7, text: "todo: Open the build log"),
        memoryDocument(id: 8, text: "correction: Use weekly review -> Use daily review"),
    ]

    let candidates = try await DeterministicMemoryExtractionProvider().candidates(from: documents)

    #expect(candidates.map(\.kind) == [.decision, .commitment, .preference, .question, .fact, .correction])
    #expect(candidates.map(\.statement).contains("This ordinary capture stays evidence only") == false)
    #expect(candidates.last?.statement == "Use daily review")
    #expect(candidates.last?.relation == .supersedes("Use weekly review"))
    #expect(candidates.allSatisfy { $0.confidence == 1 && !$0.evidence.excerpt.isEmpty })
}

@Test func transcriptionCorrectionBecomesEvidenceBackedMemoryCandidate() async throws {
    let document = RecallDocument(
        evidenceID: RecallEvidenceID(kind: .correction, id: UUID()),
        title: "Voice correction",
        text: "Call Mira\ncall mirror",
        occurredAt: Date(timeIntervalSince1970: 10)
    )

    let candidate = try #require(
        await DeterministicMemoryExtractionProvider().candidates(from: [document]).first
    )

    #expect(candidate.kind == .correction)
    #expect(candidate.statement == "Call Mira")
    #expect(candidate.relation == .supersedes("call mirror"))
    #expect(candidate.evidence.evidenceID == document.evidenceID)
}

@Test func memoryCandidateRejectsEmptyAndOversizedStatements() {
    let evidence = MemoryEvidence(
        evidenceID: RecallEvidenceID(kind: .capture, id: UUID()),
        excerpt: "evidence", occurredAt: .distantPast, availability: .retained
    )
    #expect(throws: WorkingMemoryError.emptyStatement) {
        _ = try MemoryCandidate(kind: .fact, statement: " ", evidence: evidence)
    }
    #expect(throws: WorkingMemoryError.statementTooLong) {
        _ = try MemoryCandidate(
            kind: .fact, statement: String(repeating: "x", count: 501), evidence: evidence
        )
    }
}

@Test func memoryEvidenceValidationRequiresTheExactReferencedExcerpt() throws {
    let document = memoryDocument(id: 20, text: "decision: Keep the launch small")
    let candidate = try memoryCandidate(
        kind: .decision, statement: "Keep the launch small", document: document
    )
    try MemoryEvidenceValidator().validate(candidate, against: [document])

    let missing = memoryDocument(id: 21, text: document.text)
    #expect(throws: WorkingMemoryError.evidenceMissing) {
        try MemoryEvidenceValidator().validate(candidate, against: [missing])
    }
    let altered = RecallDocument(
        evidenceID: document.evidenceID,
        title: document.title,
        text: "decision: Keep the launch quiet",
        occurredAt: document.occurredAt
    )
    #expect(throws: WorkingMemoryError.evidenceExcerptMismatch) {
        try MemoryEvidenceValidator().validate(candidate, against: [altered])
    }
}

@Test func equivalentMemoryMergesEvidenceAndDuplicateEvidenceIsIdempotent() throws {
    let firstDocument = memoryDocument(id: 30, text: "remember: Staging closes Friday")
    let secondDocument = memoryDocument(id: 31, text: "REMEMBER: staging closes Friday.")
    let first = try memoryCandidate(kind: .fact, statement: "Staging closes Friday", document: firstDocument)
    let second = try memoryCandidate(kind: .fact, statement: "staging closes Friday.", document: secondDocument)
    let ledger = TemporalMemoryLedger()
    let recordID = UUID(uuidString: "40000000-0000-0000-0000-000000000030")!

    let once = ledger.applying(first, to: [], at: .distantPast, id: recordID)
    let twice = ledger.applying(second, to: once, at: Date(timeIntervalSince1970: 20))
    let duplicate = ledger.applying(second, to: twice, at: Date(timeIntervalSince1970: 30))

    #expect(twice.count == 1)
    #expect(twice[0].id == recordID)
    #expect(twice[0].version == 2)
    #expect(twice[0].evidence.count == 2)
    #expect(duplicate == twice)
}

@Test func explicitCorrectionSupersedesMatchingCurrentMemoryAndRetainsHistory() throws {
    let oldDocument = memoryDocument(id: 40, text: "prefer: Weekly review")
    let correctionDocument = memoryDocument(id: 41, text: "correction: weekly review -> Daily review")
    let old = try memoryCandidate(kind: .preference, statement: "Weekly review", document: oldDocument)
    let correction = try memoryCandidate(
        kind: .correction,
        statement: "Daily review",
        document: correctionDocument,
        relation: .supersedes("weekly review")
    )
    let ledger = TemporalMemoryLedger()
    let oldID = UUID(uuidString: "40000000-0000-0000-0000-000000000040")!
    let correctionID = UUID(uuidString: "40000000-0000-0000-0000-000000000041")!

    let initial = ledger.applying(old, to: [], at: .distantPast, id: oldID)
    let revised = ledger.applying(
        correction, to: initial, at: Date(timeIntervalSince1970: 40), id: correctionID
    )

    #expect(revised.count == 2)
    #expect(revised.first(where: { $0.id == oldID })?.state == .superseded(by: correctionID))
    #expect(revised.first(where: { $0.id == correctionID })?.state == .active)
}

@Test func differentClaimsRemainActiveWithoutExplicitCorrection() throws {
    let ledger = TemporalMemoryLedger()
    let a = try memoryCandidate(
        kind: .fact, statement: "Launch is Friday",
        document: memoryDocument(id: 50, text: "remember: Launch is Friday")
    )
    let b = try memoryCandidate(
        kind: .fact, statement: "Launch is Monday",
        document: memoryDocument(id: 51, text: "remember: Launch is Monday")
    )

    let result = ledger.applying(b, to: ledger.applying(a, to: []))

    #expect(result.count == 2)
    #expect(result.allSatisfy { $0.state == .active })
}

@Test func revalidationExpiresMissingEvidenceWithoutDeletingTheClaim() throws {
    let keptDocument = memoryDocument(id: 60, text: "remember: Keep the source")
    let missingDocument = memoryDocument(id: 61, text: "remember: Missing source")
    let ledger = TemporalMemoryLedger()
    let kept = try memoryCandidate(kind: .fact, statement: "Keep the source", document: keptDocument)
    let missing = try memoryCandidate(kind: .fact, statement: "Missing source", document: missingDocument)
    let records = ledger.applying(missing, to: ledger.applying(kept, to: []))

    let result = ledger.revalidated(records, against: [keptDocument])

    #expect(result.count == 2)
    #expect(result.first(where: { $0.statement == "Keep the source" })?.state == .active)
    let expired = result.first(where: { $0.statement == "Missing source" })
    #expect(expired?.state == .evidenceExpired)
    #expect(expired?.evidence.first?.availability == .expired)
}

@Test func compilerIsIdempotentAndExplicitCorrectionKeepsSupersededHistory() async throws {
    let old = memoryDocument(id: 70, text: "prefer: Weekly review")
    let correction = memoryDocument(id: 71, text: "correction: Weekly review -> Daily review")
    let source = FixedMemoryDocumentSource(documents: [old, correction])
    let repository = WorkingMemoryRepository()
    let compiler = WorkingMemoryCompiler(
        source: source,
        provider: DeterministicMemoryExtractionProvider(),
        repository: repository,
        now: { Date(timeIntervalSince1970: 100) }
    )

    let first = try await compiler.compile()
    let second = try await compiler.compile()

    #expect(first == second)
    #expect(first.count == 2)
    #expect(first.contains { $0.statement == "Daily review" && $0.state == .active })
    #expect(first.contains {
        guard $0.statement == "Weekly review" else { return false }
        if case .superseded = $0.state { return true }
        return false
    })
}

@Test func memoryEvaluationReportsCoverageContradictionsAndCurrentState() async throws {
    let fixture = MemoryEvaluationFixture(
        documents: [
            memoryDocument(id: 80, text: "remember: Launch is Friday"),
            memoryDocument(id: 81, text: "remember: Launch is Monday"),
            memoryDocument(id: 82, text: "prefer: Weekly review"),
            memoryDocument(id: 83, text: "correction: Weekly review -> Daily review"),
            memoryDocument(id: 84, text: "ordinary prose is ignored"),
        ],
        expectations: [
            MemoryEvaluationExpectation(statement: "Launch is Friday", state: .active),
            MemoryEvaluationExpectation(statement: "Launch is Monday", state: .active),
            MemoryEvaluationExpectation(statement: "Weekly review", state: .superseded),
            MemoryEvaluationExpectation(statement: "Daily review", state: .active),
        ],
        contradictionGroups: [["Launch is Friday", "Launch is Monday"]]
    )

    let report = try await MemoryFixtureEvaluator().evaluate(fixture)

    #expect(report.acceptedMemoryCount == 4)
    #expect(report.evidenceCoverage == 1)
    #expect(report.contradictionPreservation == 1)
    #expect(report.currentStateAccuracy == 1)

    let empty = MemoryEvaluationReport(
        records: [], documents: [], expectations: [], contradictionGroups: []
    )
    #expect(empty.acceptedMemoryCount == 0)
    #expect(empty.evidenceCoverage == nil)
    #expect(empty.contradictionPreservation == nil)
    #expect(empty.currentStateAccuracy == nil)
}

private func memoryDocument(id: Int, text: String) -> RecallDocument {
    RecallDocument(
        evidenceID: RecallEvidenceID(
            kind: .capture,
            id: UUID(uuidString: String(format: "30000000-0000-0000-0000-%012d", id))!
        ),
        title: "Capture", text: text,
        occurredAt: Date(timeIntervalSince1970: Double(id))
    )
}

private func memoryCandidate(
    kind: MemoryKind,
    statement: String,
    document: RecallDocument,
    relation: MemoryRelation = .none
) throws -> MemoryCandidate {
    try MemoryCandidate(
        kind: kind,
        statement: statement,
        evidence: MemoryEvidence(
            evidenceID: document.evidenceID,
            excerpt: document.text,
            occurredAt: document.occurredAt
        ),
        relation: relation
    )
}

private struct FixedMemoryDocumentSource: RecallDocumentProviding {
    let documentsValue: [RecallDocument]

    init(documents: [RecallDocument]) {
        documentsValue = documents
    }

    func documents() async throws -> [RecallDocument] { documentsValue }
}

private actor WorkingMemoryRepository: ThoughtRepository {
    private var storedMemory: [MemoryRecord] = []

    func save(memoryRecords: [MemoryRecord]) async throws { storedMemory = memoryRecords }
    func memoryRecords() async throws -> [MemoryRecord] { storedMemory }
    func save(capture: RawCapture) async throws {}
    func save(proposal: ClarificationProposal) async throws {}
    func save(intention: Intention) async throws {}
    func captures(disposition: Disposition) async throws -> [RawCapture] { [] }
    func intention(id: UUID) async throws -> Intention? { nil }
    func openIntentions() async throws -> [Intention] { [] }
    func proposal(captureID: UUID) async throws -> ClarificationProposal? { nil }
}
