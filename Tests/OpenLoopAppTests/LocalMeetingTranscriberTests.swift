import Testing
import WhisperKit
@testable import OpenLoopApp

@Test func whisperProgressEstimateIsBoundedForLongMeetings() {
    #expect(WhisperKitMeetingTranscriber.estimatedFraction(
        windowID: 0,
        inputAudioSeconds: 30,
        duration: 1_500
    ) == 0.02)
    #expect(WhisperKitMeetingTranscriber.estimatedFraction(
        windowID: 90,
        inputAudioSeconds: 2_000,
        duration: 1_500
    ) == 0.98)
    let fallback = WhisperKitMeetingTranscriber.estimatedFraction(
        windowID: 2,
        inputAudioSeconds: 0,
        duration: 0
    )
    #expect(abs(fallback - 0.15) < 0.000_001)
}

@Test func languageSummaryPreservesFirstSeenLanguages() {
    #expect(WhisperKitMeetingTranscriber.languageSummary(["en", "en", "hi", "hi"]) == "en + hi")
    #expect(WhisperKitMeetingTranscriber.languageSummary(["hi"]) == "hi")
    #expect(WhisperKitMeetingTranscriber.languageSummary(["", "  "]) == nil)
}

@Test func blankWhisperContainersRequireWholeRecordingFallback() {
    let blank = TranscriptionResult(
        text: "",
        segments: [],
        language: "en",
        timings: TranscriptionTimings()
    )
    let spoken = TranscriptionResult(
        text: "Hello",
        segments: [TranscriptionSegment(start: 0, end: 1, text: "Hello")],
        language: "en",
        timings: TranscriptionTimings()
    )

    #expect(!WhisperKitMeetingTranscriber.hasUsableTranscript([blank]))
    #expect(WhisperKitMeetingTranscriber.hasUsableTranscript([spoken]))
    #expect(!WhisperKitMeetingTranscriber.allUtterancesHaveUsableTranscript([
        [spoken],
        [blank],
    ]))
    #expect(WhisperKitMeetingTranscriber.allUtterancesHaveUsableTranscript([
        [spoken],
        [spoken],
    ]))
}
