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

@Test func blankWhisperContainersRequireWholeRecordingFallback() async {
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
    #expect(WhisperKitMeetingTranscriber.shouldRetryWithoutPrompt(
        [blank],
        promptTokens: [1, 2]
    ))
    #expect(!WhisperKitMeetingTranscriber.shouldRetryWithoutPrompt(
        [spoken],
        promptTokens: [1, 2]
    ))
    #expect(!WhisperKitMeetingTranscriber.shouldRetryWithoutPrompt(
        [blank],
        promptTokens: nil
    ))
    #expect(WhisperKitMeetingTranscriber.participantPrompt(
        from: "Participants: Dhruv. Multilingual guidance follows."
    ) == "Participants: Dhruv.")
    #expect(WhisperKitMeetingTranscriber.participantPrompt(
        from: "Multilingual conversation in English and Hindi."
    ) == nil)

    let gate = TranscriptionAttemptGate()
    let firstAttempt = gate.beginAttempt()
    #expect(gate.isCurrent(firstAttempt))
    let secondAttempt = gate.beginAttempt()
    #expect(!gate.isCurrent(firstAttempt))
    #expect(gate.isCurrent(secondAttempt))
    let probe = TranscriptionDeliveryProbe()
    #expect(gate.schedule(attempt: secondAttempt) {
        await probe.record()
    })
    await gate.invalidateAndDrain()
    #expect(!gate.isCurrent(secondAttempt))
    let countAfterDrain = await probe.count
    await Task.yield()
    #expect(await probe.count == countAfterDrain)
}

private actor TranscriptionDeliveryProbe {
    private(set) var count = 0

    func record() {
        count += 1
    }
}
