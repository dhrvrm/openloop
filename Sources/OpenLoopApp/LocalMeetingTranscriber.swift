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

    func transcribe(
        audioURL: URL,
        languageCode: String?,
        progress: @escaping @Sendable (MeetingTranscriptionProgress) async -> Void
    ) async throws -> LocalTranscriptionOutput

    func diagnostics() async -> MeetingEngineDiagnostics
}

extension MeetingTranscribing {
    func transcribe(
        audioURL: URL,
        languageCode: String?,
        progress: @escaping @Sendable (MeetingTranscriptionProgress) async -> Void
    ) async throws -> LocalTranscriptionOutput {
        try await transcribe(audioURL: audioURL, progress: progress)
    }

    func diagnostics() async -> MeetingEngineDiagnostics {
        .checking
    }
}

actor WhisperKitMeetingTranscriber: MeetingTranscribing {
    nonisolated let modelIdentifier: String
    private let modelStorageURL: URL
    private let speakerDiarizationEnabled: Bool
    private let contextPrompt: String?
    private var whisperKit: WhisperKit?
    private var speakerKit: SpeakerKit?

    init(
        modelIdentifier: String = "large-v3-v20240930_626MB",
        modelStorageURL: URL,
        speakerDiarizationEnabled: Bool = true,
        contextPrompt: String? = nil
    ) {
        self.modelIdentifier = modelIdentifier
        self.modelStorageURL = modelStorageURL
        self.speakerDiarizationEnabled = speakerDiarizationEnabled
        self.contextPrompt = contextPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
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
        try await transcribe(audioURL: audioURL, languageCode: nil, progress: progress)
    }

    func transcribe(
        audioURL: URL,
        languageCode: String?,
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
                        : "Transcribing locally",
                    previewText: update.text
                ))
            }
            return !Task.isCancelled
        }

        let promptTokens = Self.promptTokens(for: contextPrompt, pipeline: pipeline)
        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: languageCode,
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: languageCode == nil,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: true,
            promptTokens: promptTokens,
            concurrentWorkerCount: 4
        )
        let windows: [TranscriptionResult]
        if languageCode == nil, duration > 0, duration <= 45 {
            let audio = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
            let ranges = UtteranceAudioChunker.ranges(in: audio)
            if ranges.count > 1 {
                var utteranceOptions = options
                utteranceOptions.promptTokens = Self.promptTokens(
                    for: Self.participantPrompt(from: contextPrompt),
                    pipeline: pipeline
                )
                windows = try await transcribeUtterances(
                    audio: audio,
                    ranges: ranges,
                    pipeline: pipeline,
                    options: utteranceOptions,
                    progress: progress
                )
            } else {
                windows = try await transcribeFile(
                    audioURL: audioURL,
                    pipeline: pipeline,
                    options: options,
                    callback: callback
                )
            }
        } else {
            windows = try await transcribeFile(
                audioURL: audioURL,
                pipeline: pipeline,
                options: options,
                callback: callback
            )
        }
        try Task.checkCancellation()
        let mapped: (segments: [TranscriptSegment], language: String?)
        if speakerDiarizationEnabled {
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
        } else {
            mapped = try Self.map(windows)
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

    private func transcribeFile(
        audioURL: URL,
        pipeline: WhisperKit,
        options: DecodingOptions,
        callback: @escaping TranscriptionCallback
    ) async throws -> [TranscriptionResult] {
        let input = AudioInputOptions(audioLoadingMode: .incremental)
        let results = await pipeline.transcribeWithResults(
            audioPaths: [audioURL.path],
            audioInputOptions: input,
            decodeOptions: options,
            callback: callback
        )
        guard let first = results.first else {
            throw MeetingTranscriptionError.emptyTranscript
        }
        return try first.get()
    }

    private func transcribeUtterances(
        audio: [Float],
        ranges: [Range<Int>],
        pipeline: WhisperKit,
        options: DecodingOptions,
        progress: @escaping @Sendable (MeetingTranscriptionProgress) async -> Void
    ) async throws -> [TranscriptionResult] {
        var collected: [TranscriptionResult] = []
        for (index, range) in ranges.enumerated() {
            try Task.checkCancellation()
            let results = try await pipeline.transcribe(
                audioArray: Array(audio[range]),
                audioArrayOffset: range.lowerBound,
                decodeOptions: options
            )
            let seekTime = Float(range.lowerBound) / Float(WhisperKit.sampleRate)
            for result in results {
                result.seekTime = seekTime
                result.segments = result.segments.map {
                    TranscriptionUtilities.updateSegmentTimings(
                        segment: $0,
                        seekOffsetIndex: range.lowerBound
                    )
                }
            }
            collected.append(contentsOf: results)
            let preview = collected
                .flatMap(\.segments)
                .map(\.text)
                .joined(separator: " ")
            await progress(.init(
                stage: .transcribing,
                fraction: min(0.98, Double(index + 1) / Double(ranges.count)),
                message: "Detecting each spoken language locally",
                previewText: preview
            ))
        }
        guard !collected.isEmpty else { throw MeetingTranscriptionError.emptyTranscript }
        return collected
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
        let language = Self.languageSummary(transcription.map(\.language))
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
        let language = languageSummary(results.map(\.language))
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

    static func languageSummary(_ languages: [String]) -> String? {
        var seen = Set<String>()
        let ordered = languages.compactMap { language -> String? in
            let value = language.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seen.insert(value).inserted else { return nil }
            return value
        }
        return ordered.isEmpty ? nil : ordered.joined(separator: " + ")
    }

    private static func participantPrompt(from context: String?) -> String? {
        guard let firstSentence = context?.split(separator: ".", maxSplits: 1).first else {
            return nil
        }
        let value = firstSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value + "."
    }

    private static func promptTokens(for prompt: String?, pipeline: WhisperKit) -> [Int]? {
        guard let prompt,
              !prompt.isEmpty,
              let tokenizer = pipeline.tokenizer else { return nil }
        let tokens = tokenizer.encode(text: " " + prompt)
            .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        return tokens.isEmpty ? nil : tokens
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
