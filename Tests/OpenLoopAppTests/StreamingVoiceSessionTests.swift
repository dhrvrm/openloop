import ADHDCore
import Foundation
import Testing
@testable import OpenLoopApp

private final class ScriptedStreamingVAD: @unchecked Sendable, StreamingVoiceActivityDetecting {
    private var script: [[StreamingVADEvent]]
    private let finishEvents: [StreamingVADEvent]
    private(set) var resetCount = 0

    init(
        script: [[StreamingVADEvent]],
        finishEvents: [StreamingVADEvent] = []
    ) {
        self.script = script
        self.finishEvents = finishEvents
    }

    func process(samples: [Float]) throws -> [StreamingVADEvent] {
        script.isEmpty ? [] : script.removeFirst()
    }

    func finish() throws -> [StreamingVADEvent] { finishEvents }

    func reset() { resetCount += 1 }
}

private final class ScriptedStreamingRecognizer: @unchecked Sendable,
    StreamingSpeechRecognizing {
    struct Call: Equatable {
        let samples: [Float]
        let context: [String]
        let isFinal: Bool
    }

    let modelIdentifier = "test-qwen"
    private var partials: [String]
    private var finals: [String]
    private(set) var calls: [Call] = []

    init(partials: [String] = [], finals: [String] = []) {
        self.partials = partials
        self.finals = finals
    }

    func transcribe(
        samples: [Float],
        sampleRate: Int,
        context: [String],
        isFinal: Bool
    ) async throws -> String {
        calls.append(Call(samples: samples, context: context, isFinal: isFinal))
        if isFinal { return finals.isEmpty ? "" : finals.removeFirst() }
        return partials.isEmpty ? "" : partials.removeFirst()
    }
}

private func frame(_ value: Float, at seconds: TimeInterval) -> StreamingVoiceFrame {
    StreamingVoiceFrame(
        samples: [Float](repeating: value, count: 320),
        capturedAt: Date(timeIntervalSince1970: seconds),
        decibels: -24
    )
}

@Test func streamingSessionUsesPrerollThenMovesPartialIntoStableFinalText() async throws {
    let vad = ScriptedStreamingVAD(script: [[], [.speechStarted], [.speechEnded]])
    let recognizer = ScriptedStreamingRecognizer(
        partials: ["release time कम"],
        finals: ["release time कम कर सकते हैं"]
    )
    let session = StreamingVoiceSession(
        vad: vad,
        recognizer: recognizer,
        configuration: StreamingVoiceConfiguration(
            prerollDuration: 0.020,
            partialResultInterval: 0.020
        ),
        context: { ["SGLC"] },
        now: { Date(timeIntervalSince1970: 2) }
    )
    try await session.start(at: Date(timeIntervalSince1970: 1))

    try await session.ingest(frame(0.1, at: 1.00))
    try await session.ingest(frame(0.2, at: 1.02))
    var snapshot = await session.snapshot()
    #expect(snapshot.phase == .speech)
    #expect(snapshot.vadState == .speech)
    #expect(snapshot.transcript.stableText.isEmpty)
    #expect(snapshot.transcript.unstableText == "release time कम")
    #expect(snapshot.latency.firstPartialMilliseconds == 1_000)

    try await session.ingest(frame(0.3, at: 1.04))
    snapshot = await session.snapshot()
    #expect(snapshot.phase == .listening)
    #expect(snapshot.vadState == .silence)
    #expect(snapshot.transcript.stableText == "release time कम कर सकते हैं")
    #expect(snapshot.transcript.unstableText.isEmpty)
    #expect(snapshot.finalizedUtteranceCount == 1)
    #expect(recognizer.calls.count == 2)
    #expect(recognizer.calls[0].samples.count == 640)
    #expect(recognizer.calls[1].samples.count == 960)
    #expect(recognizer.calls.allSatisfy { $0.context == ["SGLC"] })
}

@Test func streamingSessionKeepsContinuousUtterancesAsIndependentStableSegments() async throws {
    let vad = ScriptedStreamingVAD(script: [
        [.speechStarted], [.speechEnded], [.speechStarted], [.speechEnded],
    ])
    let recognizer = ScriptedStreamingRecognizer(finals: ["पहला विचार", "second thought"])
    let session = StreamingVoiceSession(
        vad: vad,
        recognizer: recognizer,
        configuration: StreamingVoiceConfiguration(partialResultInterval: 10)
    )
    try await session.start()

    try await session.ingest(frame(0.1, at: 1))
    try await session.ingest(frame(0.2, at: 1.02))
    try await session.ingest(frame(0.3, at: 1.04))
    try await session.ingest(frame(0.4, at: 1.06))

    let snapshot = await session.snapshot()
    #expect(snapshot.transcript.stableSegments == ["पहला विचार", "second thought"])
    #expect(snapshot.transcript.visibleText == "पहला विचार second thought")
    #expect(snapshot.finalizedUtteranceCount == 2)
}

@Test func stoppingActiveSpeechRunsIndependentFinalDecodeAndMeasuresLatency() async throws {
    let vad = ScriptedStreamingVAD(
        script: [[.speechStarted]],
        finishEvents: [.speechEnded]
    )
    let recognizer = ScriptedStreamingRecognizer(finals: ["final text"])
    let session = StreamingVoiceSession(
        vad: vad,
        recognizer: recognizer,
        now: { Date(timeIntervalSince1970: 5.4) }
    )
    try await session.start(at: Date(timeIntervalSince1970: 4))
    try await session.ingest(frame(0.5, at: 4.1))

    try await session.stop(at: Date(timeIntervalSince1970: 5))

    let snapshot = await session.snapshot()
    #expect(snapshot.phase == .completed)
    #expect(snapshot.transcript.stableText == "final text")
    #expect(snapshot.latency.stopToFinalMilliseconds! > 399)
    #expect(snapshot.latency.stopToFinalMilliseconds! < 401)
    #expect(recognizer.calls == [ScriptedStreamingRecognizer.Call(
        samples: [Float](repeating: 0.5, count: 320),
        context: [],
        isFinal: true
    )])
}

@Test func streamingSessionRejectsWrongAudioShapeAndCancellationDiscardsText() async throws {
    let vad = ScriptedStreamingVAD(script: [[.speechStarted]])
    let recognizer = ScriptedStreamingRecognizer()
    let session = StreamingVoiceSession(vad: vad, recognizer: recognizer)
    try await session.start()

    await #expect(throws: StreamingVoiceSessionError.invalidSampleRate(
        expected: 16_000,
        actual: 44_100
    )) {
        try await session.ingest(StreamingVoiceFrame(
            samples: [Float](repeating: 0, count: 320),
            sampleRate: 44_100
        ))
    }
    try await session.ingest(frame(0.4, at: 1))
    await session.cancel()

    let snapshot = await session.snapshot()
    #expect(snapshot.phase == .cancelled)
    #expect(snapshot.transcript.visibleText.isEmpty)
    #expect(snapshot.vadState == .silence)
    #expect(vad.resetCount == 2)
    #expect(recognizer.calls.isEmpty)
}
