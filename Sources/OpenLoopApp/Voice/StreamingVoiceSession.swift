import ADHDCore
import Foundation
@preconcurrency import Qwen3ASR
@preconcurrency import SpeechVAD

enum StreamingVADEvent: Equatable, Sendable {
    case speechStarted
    case speechEnded
}

protocol StreamingVoiceActivityDetecting: AnyObject, Sendable {
    func process(samples: [Float]) throws -> [StreamingVADEvent]
    func finish() throws -> [StreamingVADEvent]
    func reset()
}

protocol StreamingSpeechRecognizing: AnyObject, Sendable {
    var modelIdentifier: String { get }
    func transcribe(
        samples: [Float],
        sampleRate: Int,
        context: [String],
        isFinal: Bool
    ) async throws -> String
}

protocol StreamingVoiceSessionBuilding: Sendable {
    func make(
        onUpdate: @escaping StreamingVoiceSession.UpdateHandler
    ) async throws -> StreamingVoiceSession
}

struct StreamingVoiceFrame: Equatable, Sendable {
    let samples: [Float]
    let sampleRate: Int
    let capturedAt: Date
    let decibels: Float?

    init(
        samples: [Float],
        sampleRate: Int = 16_000,
        capturedAt: Date = .now,
        decibels: Float? = nil
    ) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.capturedAt = capturedAt
        self.decibels = decibels
    }
}

struct StreamingVoiceConfiguration: Equatable, Sendable {
    let sampleRate: Int
    let minimumFrameDuration: TimeInterval
    let maximumFrameDuration: TimeInterval
    let prerollDuration: TimeInterval
    let partialResultInterval: TimeInterval

    init(
        sampleRate: Int = 16_000,
        minimumFrameDuration: TimeInterval = 0.020,
        maximumFrameDuration: TimeInterval = 0.032,
        prerollDuration: TimeInterval = 0.240,
        partialResultInterval: TimeInterval = 0.600
    ) {
        self.sampleRate = sampleRate
        self.minimumFrameDuration = minimumFrameDuration
        self.maximumFrameDuration = maximumFrameDuration
        self.prerollDuration = prerollDuration
        self.partialResultInterval = partialResultInterval
    }
}

enum StreamingVoiceSessionError: Error, Equatable {
    case sessionAlreadyRunning
    case sessionNotRunning
    case invalidSampleRate(expected: Int, actual: Int)
    case invalidFrameLength(minimum: Int, maximum: Int, actual: Int)
}

/// Headless continuous voice session. Audio capture feeds this actor with
/// 20–32 ms, 16 kHz mono frames; VAD and recognition are injected and testable.
actor StreamingVoiceSession {
    typealias Clock = @Sendable () -> Date
    typealias UpdateHandler = @Sendable (VoiceSessionSnapshot) async -> Void

    private let id: UUID
    private let vad: any StreamingVoiceActivityDetecting
    private let recognizer: any StreamingSpeechRecognizing
    private let configuration: StreamingVoiceConfiguration
    private let context: @Sendable () async -> [String]
    private let now: Clock
    private let onUpdate: UpdateHandler

    private var phase = VoiceSessionPhase.idle
    private var vadState = VoiceSessionVADState.silence
    private var stableSegments: [String] = []
    private var unstableText = ""
    private var inputDecibels: Float?
    private var processedFrameCount = 0
    private var finalizedUtteranceCount = 0
    private var firstPartialMilliseconds: Double?
    private var stopToFinalMilliseconds: Double?
    private var failureMessage: String?
    private var startedAt: Date?
    private var stopRequestedAt: Date?
    private var preroll: [Float] = []
    private var utterance: [Float] = []
    private var samplesSincePartial = 0

    init(
        id: UUID = UUID(),
        vad: any StreamingVoiceActivityDetecting,
        recognizer: any StreamingSpeechRecognizing,
        configuration: StreamingVoiceConfiguration = StreamingVoiceConfiguration(),
        context: @escaping @Sendable () async -> [String] = { [] },
        now: @escaping Clock = { .now },
        onUpdate: @escaping UpdateHandler = { _ in }
    ) {
        self.id = id
        self.vad = vad
        self.recognizer = recognizer
        self.configuration = configuration
        self.context = context
        self.now = now
        self.onUpdate = onUpdate
    }

    func start(at date: Date? = nil) async throws {
        guard phase == .idle || phase == .completed || phase == .cancelled || phase == .failed else {
            throw StreamingVoiceSessionError.sessionAlreadyRunning
        }
        vad.reset()
        phase = .listening
        vadState = .silence
        stableSegments = []
        unstableText = ""
        inputDecibels = nil
        processedFrameCount = 0
        finalizedUtteranceCount = 0
        firstPartialMilliseconds = nil
        stopToFinalMilliseconds = nil
        failureMessage = nil
        startedAt = date ?? now()
        stopRequestedAt = nil
        preroll = []
        utterance = []
        samplesSincePartial = 0
        await publish()
    }

    func ingest(_ frame: StreamingVoiceFrame) async throws {
        guard phase == .listening || phase == .speech else {
            throw StreamingVoiceSessionError.sessionNotRunning
        }
        try validate(frame)
        let wasInSpeech = phase == .speech
        let events = try vad.process(samples: frame.samples)
        processedFrameCount += 1
        inputDecibels = frame.decibels.map { min(0, max(-60, $0)) }

        if wasInSpeech {
            utterance.append(contentsOf: frame.samples)
            samplesSincePartial += frame.samples.count
        }

        for event in events {
            switch event {
            case .speechStarted where phase == .listening:
                phase = .speech
                vadState = .speech
                utterance = preroll + frame.samples
                samplesSincePartial = frame.samples.count
                preroll.removeAll(keepingCapacity: true)
            case .speechEnded where phase == .speech:
                try await finalizeCurrentUtterance()
            case .speechStarted, .speechEnded:
                break
            }
        }

        if phase == .speech, samplesSincePartial >= partialIntervalSamples {
            try await updatePartial()
        } else if phase == .listening {
            appendToPreroll(frame.samples)
        }
        await publish()
    }

    func stop(at date: Date? = nil) async throws {
        guard phase == .listening || phase == .speech || phase == .decoding else {
            throw StreamingVoiceSessionError.sessionNotRunning
        }
        stopRequestedAt = date ?? now()
        if phase == .speech {
            _ = try vad.finish()
            try await finalizeCurrentUtterance()
        } else if phase == .listening {
            phase = .completed
            recordStopLatency()
        }
        await publish()
    }

    func cancel() async {
        vad.reset()
        phase = .cancelled
        vadState = .silence
        stableSegments = []
        unstableText = ""
        inputDecibels = nil
        preroll = []
        utterance = []
        samplesSincePartial = 0
        stopRequestedAt = nil
        await publish()
    }

    func snapshot() -> VoiceSessionSnapshot {
        VoiceSessionSnapshot(
            id: id,
            phase: phase,
            vadState: vadState,
            transcript: VoiceSessionTranscript(
                stableSegments: stableSegments,
                unstableText: unstableText
            ),
            inputDecibels: inputDecibels,
            activeRecognizer: recognizer.modelIdentifier,
            processedFrameCount: processedFrameCount,
            finalizedUtteranceCount: finalizedUtteranceCount,
            latency: VoiceSessionLatency(
                firstPartialMilliseconds: firstPartialMilliseconds,
                stopToFinalMilliseconds: stopToFinalMilliseconds
            ),
            failureMessage: failureMessage
        )
    }

    private var partialIntervalSamples: Int {
        max(1, Int(configuration.partialResultInterval * Double(configuration.sampleRate)))
    }

    private var maximumPrerollSamples: Int {
        max(0, Int(configuration.prerollDuration * Double(configuration.sampleRate)))
    }

    private func validate(_ frame: StreamingVoiceFrame) throws {
        guard frame.sampleRate == configuration.sampleRate else {
            throw StreamingVoiceSessionError.invalidSampleRate(
                expected: configuration.sampleRate,
                actual: frame.sampleRate
            )
        }
        let minimum = Int(configuration.minimumFrameDuration * Double(configuration.sampleRate))
        let maximum = Int(configuration.maximumFrameDuration * Double(configuration.sampleRate))
        guard (minimum...maximum).contains(frame.samples.count) else {
            throw StreamingVoiceSessionError.invalidFrameLength(
                minimum: minimum,
                maximum: maximum,
                actual: frame.samples.count
            )
        }
    }

    private func appendToPreroll(_ samples: [Float]) {
        guard maximumPrerollSamples > 0 else { return }
        preroll.append(contentsOf: samples)
        if preroll.count > maximumPrerollSamples {
            preroll.removeFirst(preroll.count - maximumPrerollSamples)
        }
    }

    private func updatePartial() async throws {
        samplesSincePartial = 0
        do {
            let value = try await recognizer.transcribe(
                samples: utterance,
                sampleRate: configuration.sampleRate,
                context: await context(),
                isFinal: false
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            unstableText = value
            if firstPartialMilliseconds == nil, let startedAt {
                firstPartialMilliseconds = max(0, now().timeIntervalSince(startedAt) * 1_000)
            }
        } catch {
            fail(error)
            throw error
        }
    }

    private func finalizeCurrentUtterance() async throws {
        guard !utterance.isEmpty else {
            vadState = .silence
            phase = stopRequestedAt == nil ? .listening : .completed
            recordStopLatency()
            return
        }
        phase = .decoding
        do {
            let value = try await recognizer.transcribe(
                samples: utterance,
                sampleRate: configuration.sampleRate,
                context: await context(),
                isFinal: true
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                stableSegments.append(value)
                finalizedUtteranceCount += 1
            }
            unstableText = ""
            utterance = []
            samplesSincePartial = 0
            vadState = .silence
            phase = stopRequestedAt == nil ? .listening : .completed
            recordStopLatency()
        } catch {
            fail(error)
            throw error
        }
    }

    private func fail(_ error: Error) {
        phase = .failed
        vadState = .silence
        failureMessage = String(describing: error)
        utterance = []
        samplesSincePartial = 0
    }

    private func recordStopLatency() {
        guard phase == .completed, stopToFinalMilliseconds == nil, let stopRequestedAt else { return }
        stopToFinalMilliseconds = max(0, now().timeIntervalSince(stopRequestedAt) * 1_000)
    }

    private func publish() async {
        await onUpdate(snapshot())
    }
}

actor LocalStreamingVoiceSessionBuilder: StreamingVoiceSessionBuilding {
    private let recognizer: any StreamingSpeechRecognizing
    private let vadStorageURL: URL
    private let context: @Sendable () async -> [String]
    private var vadModel: SileroVADModel?

    init(
        recognizer: any StreamingSpeechRecognizing,
        vadStorageURL: URL,
        context: @escaping @Sendable () async -> [String] = { [] }
    ) {
        self.recognizer = recognizer
        self.vadStorageURL = vadStorageURL
        self.context = context
    }

    func make(
        onUpdate: @escaping StreamingVoiceSession.UpdateHandler
    ) async throws -> StreamingVoiceSession {
        let model: SileroVADModel
        if let vadModel {
            model = vadModel
        } else {
            try FileManager.default.createDirectory(
                at: vadStorageURL,
                withIntermediateDirectories: true
            )
            model = try await SileroVADModel.fromPretrained(
                cacheDir: vadStorageURL,
                offlineMode: false
            )
            vadModel = model
        }
        return StreamingVoiceSession(
            vad: SileroStreamingVoiceActivityDetector(model: model),
            recognizer: recognizer,
            context: context,
            onUpdate: onUpdate
        )
    }
}

@MainActor
final class StreamingVoiceFramePump {
    private let session: StreamingVoiceSession
    private let maximumPendingFrames: Int
    private var pendingFrames: [StreamingVoiceFrame] = []
    private var worker: Task<Void, Never>?
    private var acceptsFrames = true

    init(session: StreamingVoiceSession, maximumPendingFrames: Int = 32) {
        self.session = session
        self.maximumPendingFrames = max(1, maximumPendingFrames)
    }

    func enqueue(_ frame: StreamingVoiceFrame) {
        guard acceptsFrames else { return }
        pendingFrames.append(frame)
        if pendingFrames.count > maximumPendingFrames {
            pendingFrames.removeFirst(pendingFrames.count - maximumPendingFrames)
        }
        startWorkerIfNeeded()
    }

    func finish() async {
        acceptsFrames = false
        await worker?.value
    }

    func cancel() {
        acceptsFrames = false
        pendingFrames.removeAll(keepingCapacity: false)
        worker?.cancel()
        worker = nil
        Task { await session.cancel() }
    }

    private func startWorkerIfNeeded() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        while !pendingFrames.isEmpty, !Task.isCancelled {
            let frame = pendingFrames.removeFirst()
            try? await session.ingest(frame)
        }
        worker = nil
        if acceptsFrames, !pendingFrames.isEmpty { startWorkerIfNeeded() }
    }
}

final class SileroStreamingVoiceActivityDetector: @unchecked Sendable,
    StreamingVoiceActivityDetecting {
    private let processor: StreamingVADProcessor

    init(model: SileroVADModel, configuration: VADConfig = .sileroDefault) {
        processor = StreamingVADProcessor(model: model, config: configuration)
    }

    func process(samples: [Float]) throws -> [StreamingVADEvent] {
        processor.process(samples: samples).map(Self.map)
    }

    func finish() throws -> [StreamingVADEvent] {
        processor.flush().map(Self.map)
    }

    func reset() {
        processor.reset()
    }

    private static func map(_ event: VADEvent) -> StreamingVADEvent {
        switch event {
        case .speechStarted: .speechStarted
        case .speechEnded: .speechEnded
        }
    }
}

final class QwenStreamingSpeechRecognizer: @unchecked Sendable, StreamingSpeechRecognizing {
    let modelIdentifier: String
    private let model: any QwenSpeechRecognizing

    init(modelIdentifier: String, model: any QwenSpeechRecognizing) {
        self.modelIdentifier = modelIdentifier
        self.model = model
    }

    func transcribe(
        samples: [Float],
        sampleRate: Int,
        context: [String],
        isFinal: Bool
    ) async throws -> String {
        model.transcribe(
            audio: samples,
            sampleRate: sampleRate,
            language: nil,
            maxTokens: QwenMeetingTranscriber.maximumTokens(
                for: Double(samples.count) / Double(sampleRate)
            ),
            context: QwenMeetingTranscriber.context(from: context)
        )
    }
}
