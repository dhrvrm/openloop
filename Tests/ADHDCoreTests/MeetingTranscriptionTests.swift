import Foundation
import Testing
@testable import ADHDCore

@Test func meetingProgressClampsAndExposesTerminalStages() {
    #expect(MeetingTranscriptionProgress(stage: .downloadingModel, fraction: -1).fraction == 0)
    #expect(MeetingTranscriptionProgress(stage: .transcribing, fraction: 2).fraction == 1)
    #expect(MeetingTranscriptionStage.ready.isTerminal)
    #expect(MeetingTranscriptionStage.failed.isTerminal)
    #expect(MeetingTranscriptionStage.cancelled.isTerminal)
    #expect(!MeetingTranscriptionStage.transcribing.isTerminal)
}

@Test func transcriptSegmentsAreOrderedAndTranscriptRejectsEmptyText() throws {
    let later = try TranscriptSegment(start: 5, end: 8, text: "  second thought  ")
    let earlier = try TranscriptSegment(start: 0, end: 4, text: "first thought")
    let transcript = try MeetingTranscript(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
        sourceName: "meeting.m4a",
        createdAt: Date(timeIntervalSince1970: 20),
        duration: 8,
        detectedLanguage: "hi",
        modelIdentifier: "openai_whisper-large-v3-v20240930_626MB",
        segments: [later, earlier]
    )

    #expect(transcript.segments.map(\.text) == ["first thought", "second thought"])
    #expect(transcript.text == "first thought\nsecond thought")
    #expect(transcript.duration == 8)
    #expect(throws: MeetingTranscriptionError.emptyTranscript) {
        _ = try MeetingTranscript(
            sourceName: "silence.wav",
            duration: 3,
            modelIdentifier: "model",
            segments: []
        )
    }
    #expect(throws: MeetingTranscriptionError.invalidSegmentRange) {
        _ = try TranscriptSegment(start: 3, end: 2, text: "bad")
    }
}

