import ADHDCore
import Foundation

enum MeetingPipelineNodeKind: String, CaseIterable, Codable, Sendable {
    case audio
    case staging
    case whisper
    case speakers
    case vault
    case recall

    var title: String {
        switch self {
        case .audio: "Audio"
        case .staging: "Local staging"
        case .whisper: "Whisper large-v3"
        case .speakers: "Speaker separation"
        case .vault: "Encrypted vault"
        case .recall: "Recall"
        }
    }

    var detail: String {
        switch self {
        case .audio: "Import or microphone"
        case .staging: "Retry-safe temporary copy"
        case .whisper: "Language + word timestamps"
        case .speakers: "Local Pyannote alignment"
        case .vault: "AES-GCM persistence"
        case .recall: "Selectable meeting evidence"
        }
    }
}

enum MeetingPipelineNodeState: String, Codable, Sendable {
    case idle
    case active
    case complete
    case attention
}

struct MeetingPipelineNode: Identifiable, Equatable, Sendable {
    let kind: MeetingPipelineNodeKind
    let state: MeetingPipelineNodeState
    var id: MeetingPipelineNodeKind { kind }

    static func project(stage: MeetingTranscriptionStage?) -> [MeetingPipelineNode] {
        MeetingPipelineNodeKind.allCases.map { kind in
            MeetingPipelineNode(kind: kind, state: state(for: kind, stage: stage))
        }
    }

    private static func state(
        for kind: MeetingPipelineNodeKind,
        stage: MeetingTranscriptionStage?
    ) -> MeetingPipelineNodeState {
        guard let stage else { return .idle }
        if stage == .ready { return .complete }
        if stage == .failed {
            return kind == .whisper ? .attention : .idle
        }
        if stage == .cancelled { return .idle }

        let activeKind: MeetingPipelineNodeKind = switch stage {
        case .requestingMicrophone, .recording: .audio
        case .preparingAudio: .staging
        case .waitingForModel, .downloadingModel, .transcribing: .whisper
        case .diarizing: .speakers
        case .saving: .vault
        case .ready: .recall
        case .failed, .cancelled: .whisper
        }
        let ordered = MeetingPipelineNodeKind.allCases
        guard let activeIndex = ordered.firstIndex(of: activeKind),
              let nodeIndex = ordered.firstIndex(of: kind) else { return .idle }
        if nodeIndex < activeIndex { return .complete }
        if nodeIndex == activeIndex { return .active }
        return .idle
    }
}

enum MeetingModelLocalState: String, Codable, Sendable {
    case downloadRequired
    case cached
    case checking

    var title: String {
        switch self {
        case .downloadRequired: "Download required"
        case .cached: "Cached locally"
        case .checking: "Checking"
        }
    }
}

struct MeetingEngineDiagnostics: Equatable, Sendable {
    var transcriptionModel: String
    var diarizationModel: String
    var transcriptionModelState: MeetingModelLocalState
    var processingLocation: String = "On this Mac"
    var modelCacheLocation: String
    var stagingLocation: String

    static let checking = MeetingEngineDiagnostics(
        transcriptionModel: "Whisper large-v3",
        diarizationModel: "SpeakerKit Pyannote",
        transcriptionModelState: .checking,
        modelCacheLocation: "OpenLoop data / Models / WhisperKit",
        stagingLocation: "OpenLoop data / Meeting Staging"
    )
}

struct MeetingPipelineEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let occurredAt: Date
    let stage: MeetingTranscriptionStage
    let message: String
    let fraction: Double

    init(
        id: UUID = UUID(),
        occurredAt: Date = .now,
        stage: MeetingTranscriptionStage,
        message: String,
        fraction: Double
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.stage = stage
        self.message = message
        self.fraction = min(max(fraction, 0), 1)
    }
}

struct MeetingPipelineEventHistory: Sendable {
    private(set) var values: [MeetingPipelineEvent] = []
    let limit: Int

    init(limit: Int = 40) {
        self.limit = max(1, limit)
    }

    mutating func record(
        stage: MeetingTranscriptionStage,
        message: String,
        fraction: Double,
        occurredAt: Date = .now
    ) {
        let bucket = Int(min(max(fraction, 0), 1) * 10)
        if let last = values.last,
           last.stage == stage,
           Int(last.fraction * 10) == bucket {
            return
        }
        values.append(MeetingPipelineEvent(
            occurredAt: occurredAt,
            stage: stage,
            message: message,
            fraction: fraction
        ))
        if values.count > limit {
            values.removeFirst(values.count - limit)
        }
    }
}
