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
