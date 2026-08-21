import Foundation
import Testing
@testable import ADHDCore

@Test func voiceSessionTranscriptKeepsStableAndUnstableRegionsSeparate() {
    let transcript = VoiceSessionTranscript(
        stableSegments: ["पहला segment", "second segment"],
        unstableText: "changing partial"
    )

    #expect(transcript.stableText == "पहला segment second segment")
    #expect(transcript.unstableText == "changing partial")
    #expect(transcript.visibleText == "पहला segment second segment changing partial")
}

@Test func voiceSessionSnapshotRoundTripsForDurableDiagnostics() throws {
    let value = VoiceSessionSnapshot(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000081")!,
        phase: .speech,
        vadState: .speech,
        transcript: VoiceSessionTranscript(
            stableSegments: ["stable"],
            unstableText: "partial"
        ),
        inputDecibels: -24,
        activeRecognizer: "qwen3-asr-0.6b",
        processedFrameCount: 9,
        finalizedUtteranceCount: 1,
        latency: VoiceSessionLatency(firstPartialMilliseconds: 420)
    )

    let data = try JSONEncoder().encode(value)
    #expect(try JSONDecoder().decode(VoiceSessionSnapshot.self, from: data) == value)
}
