import Foundation

public enum MeetingTranscriptionStage: String, Codable, CaseIterable, Sendable {
    case requestingMicrophone
    case recording
    case waitingForModel
    case downloadingModel
    case preparingAudio
    case transcribing
    case diarizing
    case saving
    case ready
    case failed
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .ready, .failed, .cancelled: true
        default: false
        }
    }
}

public struct MeetingTranscriptionProgress: Codable, Equatable, Sendable {
    public let stage: MeetingTranscriptionStage
    public let fraction: Double
    public let message: String?

    public init(
        stage: MeetingTranscriptionStage,
        fraction: Double,
        message: String? = nil
    ) {
        self.stage = stage
        self.fraction = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        self.message = message
    }
}

public enum MeetingTranscriptionError: Error, Equatable, Sendable {
    case emptySegment
    case invalidSegmentRange
    case emptyTranscript
    case unsupportedAudioFormat(String)
    case localModelUnavailable
    case persistenceUnsupported
}

public struct TranscriptSegment: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String
    public let speaker: String?

    public init(
        id: UUID = UUID(),
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        speaker: String? = nil
    ) throws {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw MeetingTranscriptionError.emptySegment }
        guard start.isFinite, end.isFinite, start >= 0, end >= start else {
            throw MeetingTranscriptionError.invalidSegmentRange
        }
        self.id = id
        self.start = start
        self.end = end
        self.text = normalized
        self.speaker = speaker?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

public struct MeetingTranscript: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sourceName: String
    public let createdAt: Date
    public let duration: TimeInterval
    public let detectedLanguage: String?
    public let modelIdentifier: String
    public let segments: [TranscriptSegment]

    public init(
        id: UUID = UUID(),
        sourceName: String,
        createdAt: Date = .now,
        duration: TimeInterval,
        detectedLanguage: String? = nil,
        modelIdentifier: String,
        segments: [TranscriptSegment]
    ) throws {
        let ordered = segments.sorted {
            if $0.start == $1.start { return $0.id.uuidString < $1.id.uuidString }
            return $0.start < $1.start
        }
        guard !ordered.isEmpty else { throw MeetingTranscriptionError.emptyTranscript }
        self.id = id
        self.sourceName = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.duration = max(duration.isFinite ? duration : 0, ordered.last?.end ?? 0)
        self.detectedLanguage = detectedLanguage?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.modelIdentifier = modelIdentifier
        self.segments = ordered
    }

    public var text: String { segments.map(\.text).joined(separator: "\n") }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
