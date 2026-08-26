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
    public let previewText: String?

    public init(
        stage: MeetingTranscriptionStage,
        fraction: Double,
        message: String? = nil,
        previewText: String? = nil
    ) {
        self.stage = stage
        self.fraction = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        self.message = message
        let normalizedPreview = previewText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.previewText = normalizedPreview?.isEmpty == false ? normalizedPreview : nil
    }
}

public enum MeetingTranscriptionError: Error, Equatable, Sendable {
    case emptySegment
    case invalidSegmentRange
    case emptyTranscript
    case unsupportedAudioFormat(String)
    case invalidSourceAudioReference
    case localModelUnavailable
    case persistenceUnsupported
}

public enum SpeakerSeparationState: Codable, Equatable, Sendable {
    case notRequested
    case complete(speakerCount: Int)
    case unavailable
}

public struct SpeakerFingerprintObservation: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let profileID: UUID
    public let localSpeakerLabel: String
    public let embedding: [Float]

    public init(
        id: UUID = UUID(),
        profileID: UUID,
        localSpeakerLabel: String,
        embedding: [Float]
    ) {
        self.id = id
        self.profileID = profileID
        self.localSpeakerLabel = localSpeakerLabel
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.embedding = embedding.allSatisfy(\.isFinite) ? embedding : []
    }
}

public struct TranscriptSegment: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String
    public let speaker: String?
    public let speakerProfileID: UUID?

    public init(
        id: UUID = UUID(),
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        speaker: String? = nil,
        speakerProfileID: UUID? = nil
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
        self.speakerProfileID = speakerProfileID
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
    public let sourceAudioFileName: String?
    public let fusionEvidence: TranscriptFusionResult?
    public let speakerSeparation: SpeakerSeparationState
    public let speakerFingerprints: [SpeakerFingerprintObservation]

    public init(
        id: UUID = UUID(),
        sourceName: String,
        createdAt: Date = .now,
        duration: TimeInterval,
        detectedLanguage: String? = nil,
        modelIdentifier: String,
        segments: [TranscriptSegment],
        sourceAudioFileName: String? = nil,
        fusionEvidence: TranscriptFusionResult? = nil,
        speakerSeparation: SpeakerSeparationState = .notRequested,
        speakerFingerprints: [SpeakerFingerprintObservation] = []
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
        self.sourceAudioFileName = try Self.validatedSourceAudioFileName(sourceAudioFileName)
        self.fusionEvidence = fusionEvidence
        self.speakerSeparation = speakerSeparation
        self.speakerFingerprints = speakerFingerprints
    }

    public var text: String { segments.map(\.text).joined(separator: "\n") }

    private static func validatedSourceAudioFileName(_ value: String?) throws -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty else { return nil }
        guard normalized != ".",
              normalized != "..",
              !normalized.contains("/"),
              !normalized.contains("\\"),
              URL(fileURLWithPath: normalized).lastPathComponent == normalized
        else { throw MeetingTranscriptionError.invalidSourceAudioReference }
        return normalized
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceName
        case createdAt
        case duration
        case detectedLanguage
        case modelIdentifier
        case segments
        case sourceAudioFileName
        case fusionEvidence
        case speakerSeparation
        case speakerFingerprints
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(UUID.self, forKey: .id),
            sourceName: values.decode(String.self, forKey: .sourceName),
            createdAt: values.decode(Date.self, forKey: .createdAt),
            duration: values.decode(TimeInterval.self, forKey: .duration),
            detectedLanguage: values.decodeIfPresent(String.self, forKey: .detectedLanguage),
            modelIdentifier: values.decode(String.self, forKey: .modelIdentifier),
            segments: values.decode([TranscriptSegment].self, forKey: .segments),
            sourceAudioFileName: values.decodeIfPresent(String.self, forKey: .sourceAudioFileName),
            fusionEvidence: values.decodeIfPresent(
                TranscriptFusionResult.self,
                forKey: .fusionEvidence
            ),
            speakerSeparation: values.decodeIfPresent(
                SpeakerSeparationState.self,
                forKey: .speakerSeparation
            ) ?? .notRequested,
            speakerFingerprints: values.decodeIfPresent(
                [SpeakerFingerprintObservation].self,
                forKey: .speakerFingerprints
            ) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(sourceName, forKey: .sourceName)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(duration, forKey: .duration)
        try values.encodeIfPresent(detectedLanguage, forKey: .detectedLanguage)
        try values.encode(modelIdentifier, forKey: .modelIdentifier)
        try values.encode(segments, forKey: .segments)
        try values.encodeIfPresent(sourceAudioFileName, forKey: .sourceAudioFileName)
        try values.encodeIfPresent(fusionEvidence, forKey: .fusionEvidence)
        try values.encode(speakerSeparation, forKey: .speakerSeparation)
        try values.encode(speakerFingerprints, forKey: .speakerFingerprints)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
