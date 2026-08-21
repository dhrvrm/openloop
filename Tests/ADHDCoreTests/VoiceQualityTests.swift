import Foundation
import Testing
@testable import ADHDCore

@Test func exactHinglishEvidenceHasPerfectQualityMetrics() throws {
    let qualityCase = try VoiceQualityCase(
        sourceAudioIdentifier: "sha256:hinglish-release-time",
        referenceTranscript: "मैं सोच रहा था कि release time कम कर सकते हैं for SGLC releases",
        languageSequence: ["hi", "en", "hi", "en"],
        domainTerms: ["release time", "SGLC"]
    )
    let attempt = try VoiceQualityAttempt(
        caseID: qualityCase.id,
        engineIdentifier: "qwen3-asr-0.6b",
        hypothesis: qualityCase.referenceTranscript,
        firstPartialMilliseconds: 320,
        stopToFinalMilliseconds: 780
    )

    let metrics = VoiceQualityMetrics(qualityCase: qualityCase, attempt: attempt)

    #expect(metrics.wordErrorRate == 0)
    #expect(metrics.devanagariCharacterErrorRate == 0)
    #expect(metrics.domainTermRecall == 1)
    #expect(metrics.droppedSpanRate == 0)
}

@Test func qualityMetricsExposeHindiErrorsMissingTermsAndDroppedSpeech() throws {
    let qualityCase = try VoiceQualityCase(
        sourceAudioIdentifier: "sha256:mixed-language-errors",
        referenceTranscript: "हम release time कम कर सकते हैं for SGLC releases",
        languageSequence: ["hi", "en", "hi", "en"],
        domainTerms: ["release time", "SGLC"]
    )
    let attempt = try VoiceQualityAttempt(
        caseID: qualityCase.id,
        engineIdentifier: "candidate",
        hypothesis: "हम release time काम कर सकते हैं",
        stopToFinalMilliseconds: 1_800
    )

    let metrics = VoiceQualityMetrics(qualityCase: qualityCase, attempt: attempt)

    #expect(metrics.wordErrorRate > 0)
    #expect(metrics.devanagariCharacterErrorRate != nil)
    #expect(metrics.devanagariCharacterErrorRate! > 0)
    #expect(metrics.domainTermRecall == 0.5)
    #expect(metrics.droppedReferenceTokenCount > 0)
    #expect(metrics.droppedSpanRate > 0)
}

@Test func qualityReportIsMicroAveragedAndGateExplainsFailures() throws {
    let exactCase = try VoiceQualityCase(
        sourceAudioIdentifier: "sha256:exact",
        referenceTranscript: "काम करो SGLC",
        languageSequence: ["hi", "en"],
        domainTerms: ["SGLC"]
    )
    let failedCase = try VoiceQualityCase(
        sourceAudioIdentifier: "sha256:failed",
        referenceTranscript: "release जल्दी करो",
        languageSequence: ["en", "hi"],
        domainTerms: ["release"]
    )
    let exact = try VoiceQualityAttempt(
        caseID: exactCase.id,
        engineIdentifier: "candidate",
        hypothesis: exactCase.referenceTranscript,
        firstPartialMilliseconds: 300,
        stopToFinalMilliseconds: 700
    )
    let failed = try VoiceQualityAttempt(
        caseID: failedCase.id,
        engineIdentifier: "candidate",
        hypothesis: "",
        firstPartialMilliseconds: 900,
        stopToFinalMilliseconds: 2_100
    )
    let report = VoiceQualityReport(evaluations: [
        VoiceQualityEvaluation(qualityCase: exactCase, attempt: exact),
        VoiceQualityEvaluation(qualityCase: failedCase, attempt: failed),
    ])

    #expect(report.caseCount == 2)
    #expect(report.attemptCount == 2)
    #expect(report.firstPartialP95Milliseconds == 900)
    #expect(report.stopToFinalP95Milliseconds == 2_100)
    #expect(!VoiceQualityGate().passes(report))
    #expect(VoiceQualityGate().violations(in: report).count >= 3)
    #expect(VoiceQualityGate().violations(in: VoiceQualityReport(evaluations: [])) == [.noEvidence])
}

@Test func qualityEvidenceRejectsAmbiguousMetadataButRetainsEmptyEngineOutput() throws {
    #expect(throws: VoiceQualityEvidenceError.emptySourceAudioIdentifier) {
        _ = try VoiceQualityCase(
            sourceAudioIdentifier: " ",
            referenceTranscript: "valid",
            languageSequence: ["en"]
        )
    }
    #expect(throws: VoiceQualityEvidenceError.emptyLanguageSequence) {
        _ = try VoiceQualityCase(
            sourceAudioIdentifier: "sha256:test",
            referenceTranscript: "valid",
            languageSequence: []
        )
    }
    let qualityCase = try VoiceQualityCase(
        sourceAudioIdentifier: "sha256:test",
        referenceTranscript: "valid",
        languageSequence: ["EN", "HI"],
        domainTerms: ["Xcode", "xCODE"]
    )
    let emptyAttempt = try VoiceQualityAttempt(
        caseID: qualityCase.id,
        engineIdentifier: "engine",
        hypothesis: "",
        stopToFinalMilliseconds: 0
    )

    #expect(qualityCase.languageSequence == ["en", "hi"])
    #expect(qualityCase.domainTerms == ["Xcode"])
    #expect(emptyAttempt.hypothesis.isEmpty)
    #expect(VoiceQualityMetrics(
        qualityCase: qualityCase,
        attempt: emptyAttempt
    ).wordErrorRate == 1)
}

@Test func releaseAuditRemainsUnprovenWithoutRepresentativeCorrectedEvidence() async throws {
    let repository = VoiceQualityAuditRepository()
    let auditor = VoiceQualityCorpusAuditor(repository: repository, minimumCaseCount: 3)

    let audit = try await auditor.audit(engineIdentifier: "qwen-local")

    #expect(audit.status == .unproven)
    #expect(audit.report.attemptCount == 0)
    #expect(audit.coverageGaps.contains(.minimumCases(actual: 0, required: 3)))
    #expect(audit.coverageGaps.contains(.missingEnglish))
    #expect(audit.coverageGaps.contains(.missingHindi))
    #expect(audit.coverageGaps.contains(.missingCodeSwitch))
}

@Test func releaseAuditUsesLatestAttemptAndOnlyBecomesComparisonReadyAfterCoveragePasses() async throws {
    let repository = VoiceQualityAuditRepository()
    let english = try VoiceQualityCase(
        sourceAudioIdentifier: "sha256:english",
        referenceTranscript: "Ship the SGLC release",
        languageSequence: ["en"],
        domainTerms: ["SGLC"],
        createdAt: Date(timeIntervalSince1970: 1)
    )
    let mixed = try VoiceQualityCase(
        sourceAudioIdentifier: "sha256:mixed",
        referenceTranscript: "release time कम करें",
        languageSequence: ["en", "hi"],
        domainTerms: ["release time"],
        createdAt: Date(timeIntervalSince1970: 2)
    )
    try await repository.save(voiceQualityCase: english)
    try await repository.save(voiceQualityCase: mixed)
    try await repository.save(voiceQualityAttempt: VoiceQualityAttempt(
        caseID: english.id,
        engineIdentifier: "qwen-local",
        hypothesis: "wrong",
        stopToFinalMilliseconds: 3_000,
        createdAt: Date(timeIntervalSince1970: 3)
    ))
    try await repository.save(voiceQualityAttempt: VoiceQualityAttempt(
        caseID: english.id,
        engineIdentifier: "qwen-local",
        hypothesis: english.referenceTranscript,
        firstPartialMilliseconds: 300,
        stopToFinalMilliseconds: 700,
        createdAt: Date(timeIntervalSince1970: 4)
    ))
    try await repository.save(voiceQualityAttempt: VoiceQualityAttempt(
        caseID: mixed.id,
        engineIdentifier: "qwen-local",
        hypothesis: mixed.referenceTranscript,
        firstPartialMilliseconds: 350,
        stopToFinalMilliseconds: 800,
        createdAt: Date(timeIntervalSince1970: 5)
    ))
    let auditor = VoiceQualityCorpusAuditor(repository: repository, minimumCaseCount: 2)

    let audit = try await auditor.audit(engineIdentifier: "qwen-local")

    #expect(audit.status == .readyForComparativeBenchmark)
    #expect(audit.report.attemptCount == 2)
    #expect(audit.report.wordErrorRate == 0)
    #expect(audit.coverageGaps.isEmpty)
    #expect(audit.thresholdViolations.isEmpty)
}

private actor VoiceQualityAuditRepository: ThoughtRepository {
    private var cases: [VoiceQualityCase] = []
    private var attempts: [VoiceQualityAttempt] = []

    func save(capture: RawCapture) async throws {}
    func save(proposal: ClarificationProposal) async throws {}
    func save(intention: Intention) async throws {}
    func proposal(captureID: UUID) async throws -> ClarificationProposal? { nil }
    func captures(disposition: Disposition) async throws -> [RawCapture] { [] }
    func intention(id: UUID) async throws -> Intention? { nil }
    func openIntentions() async throws -> [Intention] { [] }
    func save(voiceQualityCase: VoiceQualityCase) async throws { cases.append(voiceQualityCase) }
    func voiceQualityCases() async throws -> [VoiceQualityCase] { cases }
    func save(voiceQualityAttempt: VoiceQualityAttempt) async throws { attempts.append(voiceQualityAttempt) }
    func voiceQualityAttempts(caseID: UUID?) async throws -> [VoiceQualityAttempt] {
        attempts.filter { caseID == nil || $0.caseID == caseID }
    }
}
