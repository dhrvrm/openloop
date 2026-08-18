import ADHDCore
import Combine
import Foundation

struct MeetingJobPresentation: Equatable, Sendable {
    var stage: MeetingTranscriptionStage?
    var fraction = 0.0
    var sourceName: String?
    var message = "Import an audio file to begin."
    var startedAt: Date?
    var modelIdentifier: String?
    var stagedAudioURL: URL?

    var isActive: Bool {
        guard let stage else { return false }
        return !stage.isTerminal
    }

    var canRetry: Bool { stage == .failed && stagedAudioURL != nil }
}

@MainActor
final class MeetingTranscriptionController: ObservableObject {
    @Published private(set) var job = MeetingJobPresentation()
    @Published private(set) var transcripts: [MeetingTranscript] = []
    @Published private(set) var engineDiagnostics = MeetingEngineDiagnostics.checking
    @Published private(set) var pipelineEvents: [MeetingPipelineEvent] = []

    private let repository: any ThoughtRepository
    private let transcriber: any MeetingTranscribing
    private let stagingDirectory: URL
    private let recorder: (any MeetingAudioRecording)?
    private var work: Task<Void, Never>?
    private var eventHistory = MeetingPipelineEventHistory()

    init(
        repository: any ThoughtRepository,
        transcriber: any MeetingTranscribing,
        stagingDirectory: URL,
        recorder: (any MeetingAudioRecording)? = nil
    ) {
        self.repository = repository
        self.transcriber = transcriber
        self.stagingDirectory = stagingDirectory
        self.recorder = recorder
    }

    func refresh() async {
        transcripts = (try? await repository.meetingTranscripts()) ?? []
        engineDiagnostics = await transcriber.diagnostics()
    }

    func importAudio(_ sourceURL: URL) {
        guard !job.isActive else { return }
        do {
            let stagedURL = try stage(sourceURL)
            start(stagedURL: stagedURL, sourceName: sourceURL.lastPathComponent)
        } catch {
            job = MeetingJobPresentation(
                stage: .failed,
                sourceName: sourceURL.lastPathComponent,
                message: Self.message(for: error)
            )
            recordEvent(stage: .failed, message: job.message, fraction: 0)
        }
    }

    func toggleRecording() async {
        guard let recorder else {
            job = MeetingJobPresentation(
                stage: .failed,
                message: "Microphone recording is unavailable. Import an audio file instead."
            )
            recordEvent(stage: .failed, message: job.message, fraction: 0)
            return
        }
        if job.stage == .recording {
            guard let url = recorder.stop() else {
                job.stage = .failed
                job.message = "The recording could not be finalized. Try again or import a file."
                recordEvent(stage: .failed, message: job.message, fraction: job.fraction)
                return
            }
            start(stagedURL: url, sourceName: "OpenLoop recording.m4a")
            return
        }
        guard !job.isActive else { return }
        job = MeetingJobPresentation(
            stage: .requestingMicrophone,
            message: "Requesting microphone access",
            startedAt: .now,
            modelIdentifier: transcriber.modelIdentifier
        )
        recordEvent(stage: .requestingMicrophone, message: job.message, fraction: 0)
        guard await recorder.requestPermission() else {
            job.stage = .failed
            job.message = "Microphone access is off. Enable OpenLoop in System Settings, or import an audio file with no permission."
            recordEvent(stage: .failed, message: job.message, fraction: 0)
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: stagingDirectory,
                withIntermediateDirectories: true
            )
            let url = stagingDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("m4a")
            try recorder.start(at: url)
            job = MeetingJobPresentation(
                stage: .recording,
                sourceName: "Live recording",
                message: "Recording locally. Press Stop to transcribe.",
                startedAt: .now,
                modelIdentifier: transcriber.modelIdentifier,
                stagedAudioURL: url
            )
            recordEvent(stage: .recording, message: job.message, fraction: 0)
        } catch {
            recorder.cancel()
            job.stage = .failed
            job.message = "Recording could not start. Check the selected microphone or import an audio file."
            recordEvent(stage: .failed, message: job.message, fraction: 0)
        }
    }

    func retry() {
        guard let stagedURL = job.stagedAudioURL else { return }
        start(stagedURL: stagedURL, sourceName: job.sourceName ?? stagedURL.lastPathComponent)
    }

    func cancel() {
        if job.stage == .recording || job.stage == .requestingMicrophone {
            recorder?.cancel()
        }
        work?.cancel()
        work = nil
        job.stage = .cancelled
        job.message = "Cancelled. The local audio copy is available to retry."
        recordEvent(stage: .cancelled, message: job.message, fraction: job.fraction)
    }

    func clearFinishedJob() {
        guard !job.isActive else { return }
        if let url = job.stagedAudioURL { try? FileManager.default.removeItem(at: url) }
        job = MeetingJobPresentation()
    }

    func deleteTranscript(id: UUID) async {
        do {
            try await repository.deleteMeetingTranscript(id: id)
            transcripts.removeAll { $0.id == id }
        } catch {
            job = MeetingJobPresentation(
                stage: .failed,
                message: "That encrypted transcript could not be removed."
            )
            recordEvent(stage: .failed, message: job.message, fraction: 0)
        }
    }

    func waitUntilSettledForTesting() async {
        while job.isActive || work != nil {
            await Task.yield()
        }
    }

    private func start(stagedURL: URL, sourceName: String) {
        job = MeetingJobPresentation(
            stage: .waitingForModel,
            fraction: 0,
            sourceName: sourceName,
            message: "Starting the local transcription engine",
            startedAt: .now,
            modelIdentifier: transcriber.modelIdentifier,
            stagedAudioURL: stagedURL
        )
        recordEvent(stage: .waitingForModel, message: job.message, fraction: 0)
        work = Task { [weak self] in
            guard let self else { return }
            engineDiagnostics = await transcriber.diagnostics()
            do {
                let output = try await transcriber.transcribe(audioURL: stagedURL) { [weak self] value in
                    await MainActor.run {
                        guard let self, self.job.isActive else { return }
                        self.apply(value)
                    }
                }
                try Task.checkCancellation()
                job.stage = .saving
                job.fraction = 1
                job.message = "Encrypting the transcript"
                recordEvent(stage: .saving, message: job.message, fraction: 1)
                let transcript = try MeetingTranscript(
                    sourceName: sourceName,
                    duration: output.duration,
                    detectedLanguage: output.detectedLanguage,
                    modelIdentifier: output.modelIdentifier,
                    segments: output.segments
                )
                try await repository.save(meetingTranscript: transcript)
                transcripts = try await repository.meetingTranscripts()
                try? FileManager.default.removeItem(at: stagedURL)
                job.stage = .ready
                job.fraction = 1
                job.message = "Transcript ready in Recall"
                job.stagedAudioURL = nil
                engineDiagnostics = await transcriber.diagnostics()
                recordEvent(stage: .ready, message: job.message, fraction: 1)
                work = nil
            } catch is CancellationError {
                job.stage = .cancelled
                job.message = "Cancelled. The local audio copy is available to retry."
                recordEvent(stage: .cancelled, message: job.message, fraction: job.fraction)
                work = nil
            } catch {
                job.stage = .failed
                job.message = Self.message(for: error)
                recordEvent(stage: .failed, message: job.message, fraction: job.fraction)
                work = nil
            }
        }
    }

    private func apply(_ progress: MeetingTranscriptionProgress) {
        job.stage = progress.stage
        job.fraction = progress.fraction
        job.message = progress.message ?? Self.title(for: progress.stage)
        recordEvent(stage: progress.stage, message: job.message, fraction: progress.fraction)
    }

    private func recordEvent(
        stage: MeetingTranscriptionStage,
        message: String,
        fraction: Double
    ) {
        eventHistory.record(stage: stage, message: message, fraction: fraction)
        pipelineEvents = eventHistory.values
    }

    private func stage(_ sourceURL: URL) throws -> URL {
        let allowed = Set(["wav", "mp3", "m4a", "mp4", "flac", "aiff", "aif", "caf"])
        let fileExtension = sourceURL.pathExtension.lowercased()
        guard allowed.contains(fileExtension) else {
            throw MeetingTranscriptionError.unsupportedAudioFormat(fileExtension)
        }
        try FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true
        )
        let destination = stagingDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }

    private static func title(for stage: MeetingTranscriptionStage) -> String {
        switch stage {
        case .requestingMicrophone: "Requesting microphone access"
        case .recording: "Recording locally"
        case .waitingForModel: "Preparing the local model"
        case .downloadingModel: "Downloading the local model"
        case .preparingAudio: "Preparing audio locally"
        case .transcribing: "Transcribing locally"
        case .diarizing: "Separating speakers locally"
        case .saving: "Encrypting the transcript"
        case .ready: "Transcript ready"
        case .failed: "Transcription needs attention"
        case .cancelled: "Transcription cancelled"
        }
    }

    private static func message(for error: Error) -> String {
        if case let MeetingTranscriptionError.unsupportedAudioFormat(value) = error {
            return "The .\(value) format is not supported. Choose WAV, MP3, M4A, MP4, FLAC, AIFF, or CAF."
        }
        if error is MeetingTranscriptionError {
            return "No usable speech was found. Keep the audio copy and retry, or choose another recording."
        }
        return "Local transcription stopped. Check your connection for the first model download, then retry."
    }
}
