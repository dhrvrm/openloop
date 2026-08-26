import ADHDCore
import Foundation
import Testing
@testable import OpenLoopApp

private actor NormalizationFixtureTranscriber: MeetingTranscribing {
    nonisolated let modelIdentifier = "fixture"
    let output: LocalTranscriptionOutput

    init(output: LocalTranscriptionOutput) {
        self.output = output
    }

    func transcribe(
        audioURL: URL,
        progress: @escaping @Sendable (MeetingTranscriptionProgress) async -> Void
    ) async throws -> LocalTranscriptionOutput {
        output
    }
}

@Test func transcriptNormalizerAppliesLearnedPhraseWithoutLosingSpeakerEvidence() async throws {
    let profileID = UUID()
    let segment = try TranscriptSegment(
        start: 0,
        end: 2,
        text: "It was tit-for-tat.",
        speaker: "Dhruv",
        speakerProfileID: profileID
    )
    let output = LocalTranscriptionOutput(
        duration: 2,
        detectedLanguage: "en",
        modelIdentifier: "fixture",
        segments: [segment],
        speakerSeparation: .complete(speakerCount: 1),
        speakerFingerprints: [LocalSpeakerFingerprint(
            localSpeakerLabel: "Speaker A",
            embedding: [1, 0]
        )]
    )
    let rule = TranscriptionNormalizationRule(
        recognized: "tit for tat",
        corrected: "tip for tap",
        scope: .personal,
        projectIdentifier: nil,
        evidenceCount: 1
    )
    let transcriber = TranscriptNormalizingTranscriber(
        base: NormalizationFixtureTranscriber(output: output),
        rules: { [rule] }
    )

    let normalized = try await transcriber.transcribe(
        audioURL: URL(fileURLWithPath: "/tmp/fixture.wav")
    ) { _ in }

    #expect(normalized.segments[0].text == "It was tip for tap.")
    #expect(normalized.segments[0].speaker == "Dhruv")
    #expect(normalized.segments[0].speakerProfileID == profileID)
    #expect(normalized.speakerSeparation == .complete(speakerCount: 1))
    #expect(normalized.speakerFingerprints == output.speakerFingerprints)
}
