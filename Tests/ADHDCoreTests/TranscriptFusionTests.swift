import Foundation
import Testing
@testable import ADHDCore

private func evidence(
    engine: String,
    text: String,
    start: TimeInterval = 0,
    end: TimeInterval = 2,
    confidence: Double? = nil
) -> TranscriptEvidence {
    TranscriptEvidence(
        engineIdentifier: engine,
        text: text,
        start: start,
        end: end,
        confidence: confidence
    )
}

@Test func exactRecognizerAgreementIsAutomaticallyAcceptedWithoutRewritingEvidence() {
    let primary = evidence(engine: "qwen", text: "Release time कम करें.")
    let secondary = evidence(engine: "whisper", text: "release time कम करें")

    let result = TranscriptFusionPolicy().fuse(
        primary: [primary],
        secondary: [secondary]
    )

    #expect(result.spans[0].resolution == .exactAgreement)
    #expect(result.spans[0].selectedText == primary.text)
    #expect(result.spans[0].primary == primary)
    #expect(result.spans[0].secondary == secondary)
    #expect(result.reviewSpans.isEmpty)
}

@Test func disagreementKeepsQwenPrimaryAndExposesBothCandidatesForReview() {
    let primary = evidence(engine: "qwen", text: "SGLC release कम करें")
    let secondary = evidence(engine: "whisper", text: "SGVC release काम करें")

    let result = TranscriptFusionPolicy().fuse(
        primary: [primary],
        secondary: [secondary],
        expectedDomainTerms: ["SGLC"]
    )

    let span = result.spans[0]
    #expect(span.resolution == .reviewRequired)
    #expect(span.selectedText == primary.text)
    #expect(span.reasons.contains(.recognizerDisagreement))
    #expect(span.primary.text == "SGLC release कम करें")
    #expect(span.secondary?.text == "SGVC release काम करें")
}

@Test func policyEscalatesLowConfidenceLanguageSwitchAndMissingTerms() {
    let value = evidence(
        engine: "qwen",
        text: "हम release जल्दी करें",
        confidence: 0.4
    )

    let reasons = TranscriptFusionPolicy().reasonsToRequestSecondary(
        for: value,
        expectedDomainTerms: ["SGLC"]
    )

    #expect(reasons == [.lowConfidence, .languageSwitch, .domainTermMissing])
    let withoutWitness = TranscriptFusionPolicy().fuse(
        primary: [value],
        secondary: [],
        expectedDomainTerms: ["SGLC"]
    )
    #expect(withoutWitness.reviewSpans.count == 1)
    #expect(withoutWitness.spans[0].reasons.contains(.secondaryEvidenceMissing))
}

@Test func highConfidenceMonolingualPrimaryDoesNotRequireSecondRecognizer() {
    let primary = evidence(
        engine: "qwen",
        text: "Send the release note",
        confidence: 0.95
    )

    let result = TranscriptFusionPolicy().fuse(primary: [primary], secondary: [])

    #expect(result.spans[0].resolution == .primaryAccepted)
    #expect(result.spans[0].reasons == [.primaryOnly])
}

@Test func requestedButUnavailableSecondaryIsNeverReportedAsPrimaryOnly() {
    let primary = evidence(
        engine: "whisper",
        text: "Clear words from one recognizer",
        confidence: 0.95
    )

    let result = TranscriptFusionPolicy().fuse(
        primary: [primary],
        secondary: [],
        secondaryWasRequested: true
    )

    #expect(result.spans[0].resolution == .reviewRequired)
    #expect(result.spans[0].reasons == [.secondaryEvidenceMissing])
}

@Test func fusionAlignsWitnessSegmentsByTimestampOverlap() {
    let first = evidence(engine: "qwen", text: "one", start: 0, end: 2)
    let second = evidence(engine: "qwen", text: "two", start: 2, end: 4)
    let witnessSecond = evidence(engine: "whisper", text: "too", start: 2, end: 4)
    let witnessFirst = evidence(engine: "whisper", text: "one", start: 0, end: 2)

    let result = TranscriptFusionPolicy().fuse(
        primary: [first, second],
        secondary: [witnessSecond, witnessFirst]
    )

    #expect(result.spans[0].secondary == witnessFirst)
    #expect(result.spans[0].resolution == .exactAgreement)
    #expect(result.spans[1].secondary == witnessSecond)
    #expect(result.spans[1].resolution == .reviewRequired)
    #expect(result.selectedText == "one\ntwo")
}

@Test func fusionDoesNotReplaceASpeakerTurnWithAWholeMeetingWindow() {
    let speakerTurn = evidence(engine: "whisper", text: "Ship the SGVC release", start: 4, end: 7)
    let broadWitness = evidence(
        engine: "qwen",
        text: "Earlier context. Ship the SGLC release. Later context.",
        start: 0,
        end: 18
    )

    let result = TranscriptFusionPolicy().fuse(
        primary: [speakerTurn],
        secondary: [broadWitness],
        expectedDomainTerms: ["SGLC"]
    )

    #expect(result.spans[0].selectedText == speakerTurn.text)
    #expect(result.spans[0].secondary == nil)
    #expect(result.spans[0].resolution == .reviewRequired)
}
