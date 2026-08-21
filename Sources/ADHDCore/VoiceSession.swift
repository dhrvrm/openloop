import Foundation

public enum VoiceSessionPhase: String, Codable, Equatable, Sendable {
    case idle
    case listening
    case speech
    case decoding
    case completed
    case cancelled
    case failed
}

public enum VoiceSessionVADState: String, Codable, Equatable, Sendable {
    case silence
    case speech
}

public struct VoiceSessionTranscript: Codable, Equatable, Sendable {
    public let stableSegments: [String]
    public let unstableText: String

    public init(stableSegments: [String] = [], unstableText: String = "") {
        self.stableSegments = stableSegments
        self.unstableText = unstableText
    }

    public var stableText: String {
        stableSegments.joined(separator: " ")
    }

    public var visibleText: String {
        [stableText, unstableText]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

public struct VoiceSessionLatency: Codable, Equatable, Sendable {
    public let firstPartialMilliseconds: Double?
    public let stopToFinalMilliseconds: Double?

    public init(
        firstPartialMilliseconds: Double? = nil,
        stopToFinalMilliseconds: Double? = nil
    ) {
        self.firstPartialMilliseconds = firstPartialMilliseconds
        self.stopToFinalMilliseconds = stopToFinalMilliseconds
    }
}

public struct VoiceSessionSnapshot: Codable, Equatable, Sendable {
    public let id: UUID
    public let phase: VoiceSessionPhase
    public let vadState: VoiceSessionVADState
    public let transcript: VoiceSessionTranscript
    public let inputDecibels: Float?
    public let activeRecognizer: String
    public let processedFrameCount: Int
    public let finalizedUtteranceCount: Int
    public let latency: VoiceSessionLatency
    public let failureMessage: String?

    public init(
        id: UUID,
        phase: VoiceSessionPhase,
        vadState: VoiceSessionVADState,
        transcript: VoiceSessionTranscript,
        inputDecibels: Float?,
        activeRecognizer: String,
        processedFrameCount: Int,
        finalizedUtteranceCount: Int,
        latency: VoiceSessionLatency,
        failureMessage: String? = nil
    ) {
        self.id = id
        self.phase = phase
        self.vadState = vadState
        self.transcript = transcript
        self.inputDecibels = inputDecibels
        self.activeRecognizer = activeRecognizer
        self.processedFrameCount = processedFrameCount
        self.finalizedUtteranceCount = finalizedUtteranceCount
        self.latency = latency
        self.failureMessage = failureMessage
    }
}
