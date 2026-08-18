import ADHDCore
import AVFoundation
import Foundation
import SpeakerKit
import WhisperKit

struct LocalTranscriptionOutput: Equatable, Sendable {
    let duration: TimeInterval
    let detectedLanguage: String?
    let modelIdentifier: String
    let segments: [TranscriptSegment]
}

protocol MeetingTranscribing: Sendable {
    var modelIdentifier: String { get }

    func transcribe(
        audioURL: URL,
        progress: @escaping @Sendable (MeetingTranscriptionProgress) async -> Void
    ) async throws -> LocalTranscriptionOutput

    func diagnostics() async -> MeetingEngineDiagnostics
}

extension MeetingTranscribing {
    func diagnostics() async -> MeetingEngineDiagnostics {
        .checking
    }
}

actor WhisperKitMeetingTranscriber: MeetingTranscribing {
    nonisolated let modelIdentifier: String
    private let modelStorageURL: URL
    private var whisperKit: WhisperKit?
    private var speakerKit: SpeakerKit?

    init(
        modelIdentifier: String = "large-v3-v20240930_626MB",
        modelStorageURL: URL
    ) {
        self.modelIdentifier = modelIdentifier
        self.modelStorageURL = modelStorageURL
    }

    func diagnostics() async -> MeetingEngineDiagnostics {
        let markerURL = modelStorageURL.appendingPathComponent("resolved-model-path")
        let isCached: Bool
        if let storedPath = try? String(contentsOf: markerURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) {
            isCached = FileManager.default.fileExists(atPath: storedPath)
        } else {
            isCached = false
        }
        return MeetingEngineDiagnostics(
            transcriptionModel: modelIdentifier,
            diarizationModel: "SpeakerKit Pyannote",
            transcriptionModelState: isCached ? .cached : .downloadRequired,
            modelCacheLocation: "OpenLoop data / Models / WhisperKit",
            stagingLocation: "OpenLoop data / Meeting Staging"
        )
    }

    func transcribe(
        audioURL: URL,
        progress: @escaping @Sendable (MeetingTranscriptionProgress) async -> Void
    ) async throws -> LocalTranscriptionOutput {
        let duration = await Self.audioDuration(audioURL)
        let pipeline = try await loadPipeline(progress: progress)
        await progress(.init(
            stage: .preparingAudio,
            fraction: 1,
            message: "Preparing audio locally"
        ))

        let callback: TranscriptionCallback = { update in
            let estimated = Self.estimatedFraction(
                windowID: update.windowId,
                inputAudioSeconds: update.timings.inputAudioSeconds,
                duration: duration
            )
            Task {
                await progress(.init(
                    stage: .transcribing,
                    fraction: estimated,
                    message: update.text.nilIfBlank == nil
                        ? "Listening across the meeting"
                        : "Transcribing locally"
                ))
            }
            return !Task.isCancelled
        }

        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: nil,
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: true,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: true,
            concurrentWorkerCount: 4
        )
        let input = AudioInputOptions(audioLoadingMode: .incremental)
        let results = await pipeline.transcribeWithResults(
            audioPaths: [audioURL.path],
            audioInputOptions: input,
            decodeOptions: options,
            callback: callback
        )
        try Task.checkCancellation()
        guard let first = results.first else {
            throw MeetingTranscriptionError.emptyTranscript
        }
        let windows = try first.get()
        let mapped: (segments: [TranscriptSegment], language: String?)
        do {
            mapped = try await diarize(
                audioURL: audioURL,
                transcription: windows,
                progress: progress
            )
        } catch {
            mapped = try Self.map(windows)
            await progress(.init(
                stage: .diarizing,
                fraction: 1,
                message: "Speaker separation was skipped; the full transcript is ready"
            ))
        }
        await progress(.init(
            stage: .transcribing,
            fraction: 1,
            message: "Local transcription complete"
        ))
        return LocalTranscriptionOutput(
            duration: max(duration, mapped.segments.last?.end ?? 0),
            detectedLanguage: mapped.language,
            modelIdentifier: modelIdentifier,
            segments: mapped.segments
        )
    }

    private func diarize(
        audioURL: URL,
        transcription: [TranscriptionResult],
        progress: @escaping @Sendable (MeetingTranscriptionProgress) async -> Void
    ) async throws -> (segments: [TranscriptSegment], language: String?) {
        await progress(.init(
            stage: .diarizing,
            fraction: 0,
            message: "Separating speakers locally"
        ))
        let audio = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
        let speakerKit: SpeakerKit
        if let loaded = self.speakerKit {
            speakerKit = loaded
        } else {
            let loaded = try await SpeakerKit(PyannoteConfig(
                download: true,
                load: true,
                verbose: false
            ))
            self.speakerKit = loaded
            speakerKit = loaded
        }
        let result = try await speakerKit.diarize(audioArray: audio) { value in
            Task {
                await progress(.init(
                    stage: .diarizing,
                    fraction: value.fractionCompleted,
                    message: "Separating speakers locally"
                ))
            }
        }
        let aligned = result.addSpeakerInfo(
            to: transcription,
            strategy: SpeakerInfoStrategy.subsegment(betweenWordThreshold: 0.15)
        )
            .flatMap { $0 }
        let segments = try aligned.compactMap { value -> TranscriptSegment? in
            let text = value.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let speaker = value.speaker.speakerId.map { "Speaker \($0 + 1)" }
            return try TranscriptSegment(
                start: TimeInterval(value.startTime),
                end: TimeInterval(value.endTime),
                text: text,
                speaker: speaker
            )
        }
        guard !segments.isEmpty else { throw MeetingTranscriptionError.emptyTranscript }
        let language = transcription.lazy.map(\.language).first(where: { !$0.isEmpty })
        return (segments, language)
    }

    private func loadPipeline(
        progress: @escaping @Sendable (MeetingTranscriptionProgress) async -> Void
    ) async throws -> WhisperKit {
        if let whisperKit { return whisperKit }
        await progress(.init(
            stage: .waitingForModel,
            fraction: 0,
            message: "Checking the local multilingual model"
        ))
        try FileManager.default.createDirectory(
            at: modelStorageURL,
            withIntermediateDirectories: true
        )
        let markerURL = modelStorageURL.appendingPathComponent("resolved-model-path")
        let folder: URL
        if let storedPath = try? String(contentsOf: markerURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           FileManager.default.fileExists(atPath: storedPath) {
            folder = URL(fileURLWithPath: storedPath, isDirectory: true)
        } else {
            folder = try await WhisperKit.download(
                variant: modelIdentifier,
                downloadBase: modelStorageURL,
                useBackgroundSession: false
            ) { value in
                Task {
                    await progress(.init(
                        stage: .downloadingModel,
                        fraction: value.fractionCompleted,
                        message: "Downloading the local accuracy model"
                    ))
                }
            }
            try folder.path.write(to: markerURL, atomically: true, encoding: .utf8)
        }
        await progress(.init(
            stage: .waitingForModel,
            fraction: 0.95,
            message: "Optimizing the model for this Mac"
        ))
        let config = WhisperKitConfig(
            model: modelIdentifier,
            downloadBase: modelStorageURL,
            modelFolder: folder.path,
            verbose: false,
            logLevel: .none,
            prewarm: true,
            load: true,
            download: false
        )
        let value = try await WhisperKit(config)
        whisperKit = value
        await progress(.init(
            stage: .waitingForModel,
            fraction: 1,
            message: "Local model ready"
        ))
        return value
    }

    static func map(_ results: [TranscriptionResult]) throws
        -> (segments: [TranscriptSegment], language: String?) {
        let segments = try results.flatMap(\.segments).compactMap { value -> TranscriptSegment? in
            guard value.text.nilIfBlank != nil, value.end >= value.start else { return nil }
            return try TranscriptSegment(
                start: TimeInterval(value.start),
                end: TimeInterval(value.end),
                text: value.text
            )
        }
        guard !segments.isEmpty else { throw MeetingTranscriptionError.emptyTranscript }
        let language = results.lazy.map(\.language).first(where: { !$0.isEmpty })
        return (segments, language)
    }

    static func estimatedFraction(
        windowID: Int,
        inputAudioSeconds: TimeInterval,
        duration: TimeInterval
    ) -> Double {
        guard duration > 0 else { return min(0.9, Double(windowID + 1) * 0.05) }
        if inputAudioSeconds > 0 {
            return min(0.98, inputAudioSeconds / duration)
        }
        return min(0.9, Double(windowID + 1) * 30 / duration)
    }

    private static func audioDuration(_ url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return 0 }
        let seconds = duration.seconds
        return seconds.isFinite ? max(0, seconds) : 0
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
