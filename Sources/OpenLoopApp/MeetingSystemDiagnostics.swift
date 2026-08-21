import ADHDCore
import Foundation

enum MeetingLanguagePreference: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic
    case hindiHinglish
    case english
    case bengali
    case marathi
    case tamil
    case telugu
    case gujarati
    case kannada
    case malayalam
    case punjabi
    case urdu
    case assamese
    case nepali
    case sanskrit
    case sindhi

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Auto detect"
        case .hindiHinglish: "Hindi / Hinglish"
        case .english: "English"
        case .bengali: "Bengali"
        case .marathi: "Marathi"
        case .tamil: "Tamil"
        case .telugu: "Telugu"
        case .gujarati: "Gujarati"
        case .kannada: "Kannada"
        case .malayalam: "Malayalam"
        case .punjabi: "Punjabi"
        case .urdu: "Urdu"
        case .assamese: "Assamese"
        case .nepali: "Nepali"
        case .sanskrit: "Sanskrit"
        case .sindhi: "Sindhi"
        }
    }

    var languageCode: String? {
        switch self {
        case .automatic: nil
        case .hindiHinglish: "hi"
        case .english: "en"
        case .bengali: "bn"
        case .marathi: "mr"
        case .tamil: "ta"
        case .telugu: "te"
        case .gujarati: "gu"
        case .kannada: "kn"
        case .malayalam: "ml"
        case .punjabi: "pa"
        case .urdu: "ur"
        case .assamese: "as"
        case .nepali: "ne"
        case .sanskrit: "sa"
        case .sindhi: "sd"
        }
    }
}

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
        case .whisper: "Qwen + Whisper"
        case .speakers: "Speaker separation"
        case .vault: "Encrypted vault"
        case .recall: "Recall"
        }
    }

    var detail: String {
        switch self {
        case .audio: "Import or microphone"
        case .staging: "Retry-safe temporary copy"
        case .whisper: "Accuracy-first text + timestamp fallback"
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
        transcriptionModel: "Qwen3-ASR · Whisper fallback",
        diarizationModel: "Whisper timestamps · SpeakerKit Pyannote fallback",
        transcriptionModelState: .checking,
        modelCacheLocation: "OpenLoop data / Models / Qwen3-ASR",
        stagingLocation: "OpenLoop data / Meeting Staging"
    )
}

struct AdvancedRuntimeProjection: Equatable, Sendable {
    let audioSignal: String
    let vadState: String
    let stableText: String
    let unstableText: String
    let activeRecognizer: String
    let fusionStatus: String
    let editorRoute: String
    let outputRoute: String

    static func project(
        job: MeetingJobPresentation,
        recordingDecibels: Float?,
        transcripts: [MeetingTranscript],
        diagnostics: MeetingEngineDiagnostics
    ) -> AdvancedRuntimeProjection {
        let latest = transcripts.max { $0.createdAt < $1.createdAt }
        let reviewCount = latest?.fusionEvidence?.reviewSpans.count ?? 0
        let isRecording = job.stage == .recording
        let decibelText = recordingDecibels.map { String(format: "%.0f dB", $0) } ?? "No live frame"
        let vad = if isRecording {
            if let recordingDecibels, recordingDecibels >= -45 { "Speech" } else { "Listening" }
        } else {
            "Idle"
        }
        let unstable = job.isActive ? (job.previewText ?? "Waiting for first partial") : "None"
        return AdvancedRuntimeProjection(
            audioSignal: decibelText,
            vadState: vad,
            stableText: latest?.text ?? "None yet",
            unstableText: unstable,
            activeRecognizer: diagnostics.transcriptionModel,
            fusionStatus: reviewCount == 0
                ? "No unresolved recognizer disagreement"
                : "\(reviewCount) span\(reviewCount == 1 ? "" : "s") need review",
            editorRoute: "Raw evidence preserved",
            outputRoute: job.stage == .saving ? "Encrypted vault · writing" : "Encrypted vault"
        )
    }
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
