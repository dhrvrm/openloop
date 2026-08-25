import ADHDCore
import Foundation
import Testing
@testable import OpenLoopApp

private actor FusionTestTranscriber: MeetingTranscribing {
    nonisolated let modelIdentifier: String
    private let output: LocalTranscriptionOutput?
    private let failure: Bool
    private var calls = 0

    init(
        modelIdentifier: String,
        text: String? = nil,
        detectedLanguage: String? = nil,
        failure: Bool = false
    ) throws {
        self.modelIdentifier = modelIdentifier
        self.failure = failure
        if let text {
            output = LocalTranscriptionOutput(
                duration: 2,
                detectedLanguage: detectedLanguage,
                modelIdentifier: modelIdentifier,
                segments: [try TranscriptSegment(start: 0, end: 2, text: text)]
            )
        } else {
            output = nil
        }
    }

    init(
        modelIdentifier: String,
        segments: [TranscriptSegment],
        detectedLanguage: String? = nil
    ) {
        self.modelIdentifier = modelIdentifier
        failure = false
        output = LocalTranscriptionOutput(
            duration: segments.last?.end ?? 0,
            detectedLanguage: detectedLanguage,
            modelIdentifier: modelIdentifier,
            segments: segments
        )
    }

    func transcribe(
        audioURL: URL,
        progress: @escaping @Sendable (MeetingTranscriptionProgress) async -> Void
    ) async throws -> LocalTranscriptionOutput {
        calls += 1
        if failure { throw MeetingTranscriptionError.localModelUnavailable }
        return try #require(output)
    }

    func callCount() -> Int { calls }
}

@Test func accuracyFirstSkipsWitnessForSimpleMonolingualPrimary() async throws {
    let primary = try FusionTestTranscriber(modelIdentifier: "qwen", text: "Send the release note")
    let witness = try FusionTestTranscriber(modelIdentifier: "whisper", text: "unused")
    let transcriber = AccuracyFirstTranscriber(
        primary: primary,
        witness: witness,
        crossCheckAllPrimarySpans: false
    )

    let output = try await transcriber.transcribe(audioURL: URL(fileURLWithPath: "/tmp/test.wav")) { _ in }

    #expect(await primary.callCount() == 1)
    #expect(await witness.callCount() == 0)
    #expect(output.segments.map(\.text) == ["Send the release note"])
    #expect(output.fusionEvidence?.spans[0].resolution == .primaryAccepted)
}

@Test func accuracyFirstSelectsWitnessWhenItRestoresExpectedTerminology() async throws {
    let primary = try FusionTestTranscriber(
        modelIdentifier: "qwen",
        text: "Can we reduce SGVC release time?"
    )
    let witness = try FusionTestTranscriber(
        modelIdentifier: "whisper",
        text: "Can we reduce SGLC release time?"
    )
    let transcriber = AccuracyFirstTranscriber(
        primary: primary,
        witness: witness,
        expectedDomainTerms: { ["SGLC"] }
    )

    let output = try await transcriber.transcribe(
        audioURL: URL(fileURLWithPath: "/tmp/test.wav")
    ) { _ in }

    #expect(output.segments.map(\.text) == ["Can we reduce SGLC release time?"])
    #expect(output.fusionEvidence?.reviewSpans.count == 1)
}

@Test func accuracyFirstCrossChecksHinglishAndPreservesDisagreement() async throws {
    let primary = try FusionTestTranscriber(
        modelIdentifier: "qwen",
        text: "हम SGLC release कम करें",
        detectedLanguage: "en + hi"
    )
    let witness = try FusionTestTranscriber(
        modelIdentifier: "whisper",
        text: "हम SGVC release काम करें",
        detectedLanguage: "en + hi"
    )
    let transcriber = AccuracyFirstTranscriber(
        primary: primary,
        witness: witness,
        expectedDomainTerms: { ["SGLC"] }
    )

    let output = try await transcriber.transcribe(audioURL: URL(fileURLWithPath: "/tmp/test.wav")) { _ in }

    #expect(await witness.callCount() == 1)
    #expect(output.segments.map(\.text) == ["हम SGLC release कम करें"])
    #expect(output.fusionEvidence?.reviewSpans.count == 1)
    #expect(output.fusionEvidence?.reviewSpans[0].secondary?.text == "हम SGVC release काम करें")
}

@Test func accuracyFirstFallsBackWhenPrimaryFails() async throws {
    let primary = try FusionTestTranscriber(modelIdentifier: "qwen", failure: true)
    let witness = try FusionTestTranscriber(modelIdentifier: "whisper", text: "fallback text")
    let transcriber = AccuracyFirstTranscriber(primary: primary, witness: witness)

    let output = try await transcriber.transcribe(audioURL: URL(fileURLWithPath: "/tmp/test.wav")) { _ in }

    #expect(output.segments.map(\.text) == ["fallback text"])
    #expect(await witness.callCount() == 1)
}

@Test func accuracyFirstPreservesCanonicalSpeakerTimelineWhenWitnessCorrectsText() async throws {
    let canonicalID = UUID()
    let primary = FusionTestTranscriber(
        modelIdentifier: "whisper-large-v3",
        segments: [try TranscriptSegment(
            id: canonicalID,
            start: 4,
            end: 7,
            text: "Ship the SGVC release",
            speaker: "Speaker 2"
        )]
    )
    let witness = FusionTestTranscriber(
        modelIdentifier: "qwen",
        segments: [try TranscriptSegment(
            start: 4,
            end: 7,
            text: "Ship the SGLC release"
        )]
    )
    let transcriber = AccuracyFirstTranscriber(
        primary: primary,
        witness: witness,
        expectedDomainTerms: { ["SGLC"] }
    )

    let output = try await transcriber.transcribe(
        audioURL: URL(fileURLWithPath: "/tmp/test.wav")
    ) { _ in }

    let segment = try #require(output.segments.first)
    #expect(segment.id == canonicalID)
    #expect(segment.start == 4)
    #expect(segment.end == 7)
    #expect(segment.speaker == "Speaker 2")
    #expect(segment.text == "Ship the SGLC release")
}

@Test func accuracyFirstAggregatesTimedWitnessForOneSpanDictationConsensus() async throws {
    let primary = FusionTestTranscriber(
        modelIdentifier: "qwen-large",
        segments: [try TranscriptSegment(
            start: 0,
            end: 6,
            text: "Can we reduce SGVC release time?"
        )]
    )
    let witness = FusionTestTranscriber(
        modelIdentifier: "whisper-large-v3",
        segments: [
            try TranscriptSegment(start: 0, end: 2.5, text: "Can we reduce"),
            try TranscriptSegment(start: 2.5, end: 6, text: "SGLC release time?"),
        ]
    )
    let transcriber = AccuracyFirstTranscriber(
        primary: primary,
        witness: witness,
        expectedDomainTerms: { ["SGLC"] }
    )

    let output = try await transcriber.transcribe(
        audioURL: URL(fileURLWithPath: "/tmp/test.wav")
    ) { _ in }

    #expect(output.segments.map(\.text) == ["Can we reduce SGLC release time?"])
    #expect(output.fusionEvidence?.spans[0].secondary?.text
        == "Can we reduce SGLC release time?")
}
