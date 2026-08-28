import Foundation
import SpeakerKit
import Testing
@testable import OpenLoopApp

@Test func whisperCppParsesMultilingualTimedOutput() throws {
    let data = Data(#"{"result":{"language":"hi"},"transcription":[{"text":" Hello","offsets":{"from":0,"to":1200},"tokens":[]},{"text":" जो भी बोलता हूँ","offsets":{"from":1200,"to":3400},"tokens":[]}]}"#.utf8)
    let document = try JSONDecoder().decode(WhisperCppDocument.self, from: data)

    #expect(document.result.language == "hi")
    #expect(document.transcription.map(\.text) == [" Hello", " जो भी बोलता हूँ"])
    #expect(document.transcription[1].offsets.from == 1_200)
}

@Test func whisperCppWaveWriterProducesMono16KPCM() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    try WhisperCppMeetingTranscriber.writeWave(samples: [-1, 0, 1], to: url)
    let data = try Data(contentsOf: url)

    #expect(String(data: data[0..<4], encoding: .utf8) == "RIFF")
    #expect(String(data: data[8..<12], encoding: .utf8) == "WAVE")
    #expect(data.count == 50)
}

@Test func whisperCppPromptUsesLearnedVocabularyWithoutManualRecordingSetup() {
    #expect(WhisperCppMeetingTranscriber.prompt(from: []) == nil)
    #expect(WhisperCppMeetingTranscriber.prompt(from: [" Dhruv ", "dhruv", "SGLC"])
        == "Vocabulary and names: Dhruv, SGLC")
}

@Test func whisperCppSplitsOneRecognitionSpanAtSpeakerChanges() throws {
    let data = Data(#"{"result":{"language":"en"},"transcription":[{"text":" first turn second turn","offsets":{"from":0,"to":4000},"tokens":[{"text":" first","offsets":{"from":0,"to":1000}},{"text":" turn","offsets":{"from":1000,"to":2000}},{"text":" second","offsets":{"from":2000,"to":3000}},{"text":" turn","offsets":{"from":3000,"to":4000}}]}]}"#.utf8)
    let document = try JSONDecoder().decode(WhisperCppDocument.self, from: data)
    let diarization = DiarizationResult(
        speakerCount: 2,
        totalFrames: 4,
        frameRate: 1,
        segments: [
            SpeakerSegment(speaker: .speakerId(0), startTime: 0, endTime: 2, frameRate: 1),
            SpeakerSegment(speaker: .speakerId(1), startTime: 2, endTime: 4, frameRate: 1),
        ]
    )

    let segments = try WhisperCppMeetingTranscriber.segmentsWithSpeakers(
        document,
        diarization: diarization
    )

    #expect(segments.map(\.text) == ["first turn", "second turn"])
    #expect(segments.map(\.speaker) == ["Speaker A", "Speaker B"])
}

@Test func whisperCppRetriesUrduDetectionAndKeepsHigherConfidenceHindiScript() throws {
    let primary = try JSONDecoder().decode(
        WhisperCppDocument.self,
        from: Data(#"{"result":{"language":"ur"},"transcription":[{"text":" اردو","offsets":{"from":0,"to":1000},"tokens":[{"text":" اردو","offsets":{"from":0,"to":1000},"p":0.91}]}]}"#.utf8)
    )
    let hindi = try JSONDecoder().decode(
        WhisperCppDocument.self,
        from: Data(#"{"result":{"language":"hi"},"transcription":[{"text":" हिंदी","offsets":{"from":0,"to":1000},"tokens":[{"text":" हिंदी","offsets":{"from":0,"to":1000},"p":0.96}]}]}"#.utf8)
    )

    #expect(WhisperCppMeetingTranscriber.shouldTryHindiAlternative(for: primary))
    #expect(WhisperCppMeetingTranscriber.preferredAutomaticDocument(
        primary: primary,
        hindiAlternative: hindi
    ).result.language == "hi")
}

@Test func whisperCppKeepsGenuineHigherConfidenceUrdu() throws {
    let primary = try JSONDecoder().decode(
        WhisperCppDocument.self,
        from: Data(#"{"result":{"language":"ur"},"transcription":[{"text":" اردو","offsets":{"from":0,"to":1000},"tokens":[{"text":" اردو","offsets":{"from":0,"to":1000},"p":0.98}]}]}"#.utf8)
    )
    let hindi = try JSONDecoder().decode(
        WhisperCppDocument.self,
        from: Data(#"{"result":{"language":"hi"},"transcription":[{"text":" हिंदी","offsets":{"from":0,"to":1000},"tokens":[{"text":" हिंदी","offsets":{"from":0,"to":1000},"p":0.95}]}]}"#.utf8)
    )

    #expect(WhisperCppMeetingTranscriber.preferredAutomaticDocument(
        primary: primary,
        hindiAlternative: hindi
    ).result.language == "ur")
}
