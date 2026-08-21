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
    var completedTranscriptID: UUID?
    var previewText: String?
    var requestedLanguage = MeetingLanguagePreference.automatic
    var recordingDuration: TimeInterval?
    var recordingPeakDecibels: Float?

    var isActive: Bool {
        guard let stage else { return false }
        return !stage.isTerminal
    }

    var canRetry: Bool {
        guard stage == .failed || stage == .cancelled || stage == .ready,
              let stagedAudioURL else { return false }
        return FileManager.default.fileExists(atPath: stagedAudioURL.path)
    }
}

@MainActor
final class MeetingTranscriptionController: ObservableObject {
    @Published private(set) var job = MeetingJobPresentation()
    @Published private(set) var transcripts: [MeetingTranscript] = []
    @Published private(set) var engineDiagnostics = MeetingEngineDiagnostics.checking
    @Published private(set) var pipelineEvents: [MeetingPipelineEvent] = []
    @Published private(set) var languagePreference = MeetingLanguagePreference.automatic
    @Published private(set) var recordingDecibels: Float?

    private let repository: any ThoughtRepository
    private let transcriber: any MeetingTranscribing
    private let stagingDirectory: URL
    private let recorder: (any MeetingAudioRecording)?
    private var work: Task<Void, Never>?
    private var eventHistory = MeetingPipelineEventHistory()
    private var recordingStartedAt: Date?
    private var peakRecordingDecibels: Float?

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
        recorder?.onDecibelUpdate = { [weak self] value in
            self?.recordingDecibels = value
            if let value {
                self?.peakRecordingDecibels = max(self?.peakRecordingDecibels ?? -60, value)
            }
        }
    }

    func refresh() async {
        transcripts = (try? await repository.meetingTranscripts()) ?? []
        engineDiagnostics = await transcriber.diagnostics()
        guard job.stage == nil,
              let transcript = transcripts
                .sorted(by: { $0.createdAt > $1.createdAt })
                .first(where: { sourceAudioURL(for: $0) != nil }),
              let sourceURL = sourceAudioURL(for: transcript)
        else { return }
        job = MeetingJobPresentation(
            stage: .ready,
            fraction: 1,
            sourceName: transcript.sourceName,
            message: "Transcript ready. Source audio is kept locally for retranscription.",
            startedAt: transcript.createdAt,
            modelIdentifier: transcript.modelIdentifier,
            stagedAudioURL: sourceURL,
            completedTranscriptID: transcript.id,
            previewText: transcript.text
        )
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

    func setLanguagePreference(_ preference: MeetingLanguagePreference) {
        guard !job.isActive else { return }
        languagePreference = preference
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
            let recordedDuration = recordingStartedAt.map { max(0, Date().timeIntervalSince($0)) }
            let recordedPeak = peakRecordingDecibels
            guard let url = recorder.stop() else {
                recordingDecibels = nil
                recordingStartedAt = nil
                peakRecordingDecibels = nil
                job.stage = .failed
                job.recordingDuration = recordedDuration
                job.recordingPeakDecibels = recordedPeak
                job.message = "The recording could not be finalized. Try again or import a file."
                recordEvent(stage: .failed, message: job.message, fraction: job.fraction)
                return
            }
            recordingDecibels = nil
            recordingStartedAt = nil
            start(
                stagedURL: url,
                sourceName: "OpenLoop recording.m4a",
                recordingDuration: recordedDuration,
                recordingPeakDecibels: recordedPeak
            )
            return
        }
        guard !job.isActive else { return }
        recordingDecibels = nil
        recordingStartedAt = nil
        peakRecordingDecibels = nil
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
        guard job.stage == .requestingMicrophone else { return }
        do {
            try FileManager.default.createDirectory(
                at: stagingDirectory,
                withIntermediateDirectories: true
            )
            let url = stagingDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("m4a")
            try recorder.start(at: url)
            let startedAt = Date.now
            recordingStartedAt = startedAt
            job = MeetingJobPresentation(
                stage: .recording,
                sourceName: "Live recording",
                message: "Recording locally. Press Stop to transcribe.",
                startedAt: startedAt,
                modelIdentifier: transcriber.modelIdentifier,
                stagedAudioURL: url
            )
            recordEvent(stage: .recording, message: job.message, fraction: 0)
        } catch {
            recorder.cancel()
            recordingDecibels = nil
            job.stage = .failed
            job.message = "Recording could not start. Check the selected microphone or import an audio file."
            recordEvent(stage: .failed, message: job.message, fraction: 0)
        }
    }

    func retry() {
        guard work == nil, job.canRetry, let stagedURL = job.stagedAudioURL else { return }
        start(
            stagedURL: stagedURL,
            sourceName: job.sourceName ?? stagedURL.lastPathComponent,
            recordingDuration: job.recordingDuration,
            recordingPeakDecibels: job.recordingPeakDecibels,
            replacingTranscriptID: job.completedTranscriptID
        )
    }

    func cancel() {
        if job.stage == .recording || job.stage == .requestingMicrophone {
            recorder?.cancel()
        }
        recordingDecibels = nil
        recordingStartedAt = nil
        peakRecordingDecibels = nil
        if let work {
            work.cancel()
            job.message = "Cancelling local transcription"
            if let stage = job.stage {
                recordEvent(stage: stage, message: job.message, fraction: job.fraction)
            }
            return
        }
        job.stage = .cancelled
        job.message = "Cancelled. The local audio copy is available to retry."
        recordEvent(stage: .cancelled, message: job.message, fraction: job.fraction)
    }

    func clearFinishedJob() {
        guard work == nil, !job.isActive else { return }
        if let url = job.stagedAudioURL { try? FileManager.default.removeItem(at: url) }
        job = MeetingJobPresentation()
    }

    func deleteTranscript(id: UUID) async {
        if job.isActive,
           job.completedTranscriptID == id,
           let activeWork = work {
            activeWork.cancel()
            await activeWork.value
        }
        let sourceURL = transcripts.first(where: { $0.id == id }).flatMap(sourceAudioURL(for:))
        do {
            try await repository.deleteMeetingTranscript(id: id)
            transcripts.removeAll { $0.id == id }
            if let sourceURL { try? FileManager.default.removeItem(at: sourceURL) }
            if job.completedTranscriptID == id {
                job = MeetingJobPresentation()
            }
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

    private func start(
        stagedURL: URL,
        sourceName: String,
        recordingDuration: TimeInterval? = nil,
        recordingPeakDecibels: Float? = nil,
        replacingTranscriptID: UUID? = nil
    ) {
        job = MeetingJobPresentation(
            stage: .waitingForModel,
            fraction: 0,
            sourceName: sourceName,
            message: "Starting the local transcription engine",
            startedAt: .now,
            modelIdentifier: transcriber.modelIdentifier,
            stagedAudioURL: stagedURL,
            completedTranscriptID: replacingTranscriptID,
            requestedLanguage: languagePreference,
            recordingDuration: recordingDuration,
            recordingPeakDecibels: recordingPeakDecibels
        )
        recordEvent(stage: .waitingForModel, message: job.message, fraction: 0)
        work = Task { [weak self] in
            guard let self else { return }
            engineDiagnostics = await transcriber.diagnostics()
            do {
                let output = try await transcriber.transcribe(
                    audioURL: stagedURL,
                    languageCode: job.requestedLanguage.languageCode
                ) { [weak self] value in
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
                let replacedTranscript = replacingTranscriptID.flatMap { replacementID in
                    transcripts.first { $0.id == replacementID }
                }
                let transcript = try MeetingTranscript(
                    id: replacingTranscriptID ?? UUID(),
                    sourceName: sourceName,
                    createdAt: replacedTranscript?.createdAt ?? .now,
                    duration: output.duration,
                    detectedLanguage: output.detectedLanguage,
                    modelIdentifier: output.modelIdentifier,
                    segments: output.segments,
                    sourceAudioFileName: stagedURL.lastPathComponent,
                    fusionEvidence: output.fusionEvidence
                )
                job.previewText = transcript.text
                try await repository.save(meetingTranscript: transcript)
                job.completedTranscriptID = transcript.id
                try Task.checkCancellation()
                transcripts = try await repository.meetingTranscripts()
                job.stage = .ready
                job.fraction = 1
                job.message = "Transcript ready below. Source audio is kept locally for retranscription."
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
                if case MeetingTranscriptionError.emptyTranscript = error {
                    job.previewText = nil
                }
                job.message = Self.message(
                    for: error,
                    recordingDuration: job.recordingDuration,
                    recordingPeakDecibels: job.recordingPeakDecibels
                )
                recordEvent(stage: .failed, message: job.message, fraction: job.fraction)
                work = nil
            }
        }
    }

    private func apply(_ progress: MeetingTranscriptionProgress) {
        job.stage = progress.stage
        job.fraction = progress.fraction
        job.message = progress.message ?? Self.title(for: progress.stage)
        if let previewText = progress.previewText {
            job.previewText = previewText
        }
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

    private func sourceAudioURL(for transcript: MeetingTranscript) -> URL? {
        guard let fileName = transcript.sourceAudioFileName else { return nil }
        let url = stagingDirectory.appendingPathComponent(fileName, isDirectory: false)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
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

    private static func message(
        for error: Error,
        recordingDuration: TimeInterval? = nil,
        recordingPeakDecibels: Float? = nil
    ) -> String {
        guard let meetingError = error as? MeetingTranscriptionError else {
            return "Local transcription stopped. Check your connection for the first model download, then retry."
        }
        switch meetingError {
        case let .unsupportedAudioFormat(value):
            return "The .\(value) format is not supported. Choose WAV, MP3, M4A, MP4, FLAC, AIFF, or CAF."
        case .emptyTranscript:
            if let recordingDuration {
                let seconds = max(0, Int(recordingDuration.rounded()))
                if let recordingPeakDecibels {
                    let peak = Int(recordingPeakDecibels.rounded())
                    if recordingPeakDecibels < -45 {
                        return "Recorded \(seconds)s, peak \(peak) dB. The microphone input was too quiet for reliable speech; move closer and try again."
                    }
                    return "Recorded \(seconds)s, peak \(peak) dB. Speech reached the microphone, but decoding returned no words. Retry runs the complete recording locally."
                }
                return "Recorded \(seconds)s, but no microphone level was measured. Check the input device and try again."
            }
            return "No usable speech was found. Keep the audio copy and retry, or choose another recording."
        case .emptySegment, .invalidSegmentRange:
            return "Speech was decoded, but its timestamps were invalid. Keep the audio copy and retry locally."
        case .invalidSourceAudioReference:
            return "The local source-audio reference was invalid. Import or record the audio again."
        case .localModelUnavailable:
            return "The local transcription model is unavailable. Check the model status in Advanced, then retry."
        case .persistenceUnsupported:
            return "The transcript could not be stored in the encrypted vault. Your audio copy is still available to retry."
        }
    }
}
