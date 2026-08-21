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
