import ADHDCore
import Foundation
@preconcurrency import Qwen3ASR
import WhisperKit

protocol QwenSpeechRecognizing: AnyObject {
    func transcribe(
        audio: [Float],
        sampleRate: Int,
        language: String?,
        maxTokens: Int,
        context: String?
    ) -> String
}

extension Qwen3ASRModel: QwenSpeechRecognizing {}

/// Accuracy-first local recognizer for dictation and meetings.
///
/// Qwen produces the final words. Whisper remains available as an automatic
/// fallback while the native Qwen model is downloading, unavailable, or
/// returns an empty result. The actor keeps Qwen resident after its first load.
actor QwenMeetingTranscriber: MeetingTranscribing, StreamingSpeechRecognizing {
    typealias ModelLoader = @Sendable (
        String,
        URL,
        @escaping @Sendable (Double, String) async -> Void
    ) async throws -> any QwenSpeechRecognizing

    nonisolated let modelIdentifier: String

    private let qwenModelID: String
    private let modelStorageURL: URL
    private let fallback: any MeetingTranscribing
    private let fallbackEnabled: Bool
    private let contextProvider: @Sendable () async -> [String]
    private let modelLoader: ModelLoader
    private let segmenter: LongFormAudioSegmenter
    private let audioConditioner = SpeechAudioConditioner()
    private var model: (any QwenSpeechRecognizing)?

    init(
        qwenModelID: String = ASRModelSize.small.defaultModelId,
        modelStorageURL: URL,
        fallback: any MeetingTranscribing,
        fallbackEnabled: Bool = true,
        contextProvider: @escaping @Sendable () async -> [String] = { [] },
        modelLoader: ModelLoader? = nil,
        segmenter: LongFormAudioSegmenter = LongFormAudioSegmenter()
    ) {
        self.qwenModelID = qwenModelID
        self.modelIdentifier = "\(qwenModelID.split(separator: "/").last.map(String.init) ?? qwenModelID) · Whisper fallback"
        self.modelStorageURL = modelStorageURL
        self.fallback = fallback
        self.fallbackEnabled = fallbackEnabled
        self.contextProvider = contextProvider
        self.modelLoader = modelLoader ?? Self.loadModel
        self.segmenter = segmenter
    }

    func diagnostics() async -> MeetingEngineDiagnostics {
        let weightsURL = modelStorageURL.appendingPathComponent("model.safetensors")
        return MeetingEngineDiagnostics(
            transcriptionModel: modelIdentifier,
            diarizationModel: "Whisper timestamps · SpeakerKit Pyannote fallback",
            transcriptionModelState: FileManager.default.fileExists(atPath: weightsURL.path)
                ? .cached
                : .downloadRequired,
            modelCacheLocation: "OpenLoop data / Models / Qwen3-ASR",
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
        samples: [Float],
        sampleRate: Int,
        context: [String],
        isFinal: Bool
    ) async throws -> String {
        let model = try await loadModelIfNeeded { _ in }
        return model.transcribe(
            audio: samples,
            sampleRate: sampleRate,
            language: nil,
            maxTokens: Self.maximumTokens(
                for: Double(samples.count) / Double(max(1, sampleRate))
            ),
            context: Self.context(from: context)
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func transcribe(
        audioURL: URL,
        languageCode: String?,
        progress: @escaping @Sendable (MeetingTranscriptionProgress) async -> Void
    ) async throws -> LocalTranscriptionOutput {
        do {
            return try await transcribeWithQwen(
                audioURL: audioURL,
                languageCode: languageCode,
                progress: progress
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard fallbackEnabled else { throw error }
            await progress(.init(
                stage: .waitingForModel,
                fraction: 0,
                message: "Qwen could not finish; switching to local Whisper"
            ))
            return try await fallback.transcribe(
                audioURL: audioURL,
                languageCode: languageCode,
                progress: progress
            )
        }
    }

    private func transcribeWithQwen(
        audioURL: URL,
        languageCode: String?,
        progress: @escaping @Sendable (MeetingTranscriptionProgress) async -> Void
    ) async throws -> LocalTranscriptionOutput {
        let model = try await loadModelIfNeeded(progress: progress)
        try Task.checkCancellation()

        await progress(.init(
            stage: .preparingAudio,
            fraction: 1,
            message: "Preparing 16 kHz speech for Qwen"
        ))
        audioConditioner.reset()
        let audio = audioConditioner.process(
            try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path),
            sampleRate: WhisperKit.sampleRate
        )
        guard !audio.isEmpty else { throw MeetingTranscriptionError.emptyTranscript }
        let duration = Double(audio.count) / Double(WhisperKit.sampleRate)
        let vocabulary = await contextProvider()

        await progress(.init(
            stage: .transcribing,
            fraction: 0.08,
            message: "Recognizing Hindi and English with Qwen"
        ))
        let windows = segmenter.windows(samples: audio, sampleRate: WhisperKit.sampleRate)
        var segments: [TranscriptSegment] = []
        for (index, window) in windows.enumerated() {
            try Task.checkCancellation()
            let windowAudio = Array(audio[window.startSample..<window.endSample])
            let windowDuration = Double(window.sampleCount) / Double(WhisperKit.sampleRate)
            let priorTranscript = segments.map(\.text).joined(separator: " ")
            let text = model.transcribe(
                audio: windowAudio,
                sampleRate: WhisperKit.sampleRate,
                language: languageCode,
                maxTokens: Self.maximumTokens(for: windowDuration),
                context: Self.context(
                    from: vocabulary,
                    priorTranscript: priorTranscript
                )
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                segments.append(try TranscriptSegment(
                    start: Double(window.startSample) / Double(WhisperKit.sampleRate),
                    end: Double(window.endSample) / Double(WhisperKit.sampleRate),
                    text: text
                ))
            }
            await progress(.init(
                stage: .transcribing,
                fraction: Double(index + 1) / Double(max(1, windows.count)),
                message: windows.count == 1
                    ? "Qwen transcription complete"
                    : "Transcribing speech part \(index + 1) of \(windows.count)",
                previewText: segments.map(\.text).joined(separator: "\n")
            ))
        }
        try Task.checkCancellation()
        guard !segments.isEmpty else { throw MeetingTranscriptionError.emptyTranscript }

        let combinedText = segments.map(\.text).joined(separator: "\n")
        let language = Self.spokenLanguageSummary(text: combinedText, requested: languageCode)
        return LocalTranscriptionOutput(
            duration: duration,
            detectedLanguage: language,
            modelIdentifier: qwenModelID,
            segments: segments
        )
    }

    private func loadModelIfNeeded(
        progress: @escaping @Sendable (MeetingTranscriptionProgress) async -> Void
    ) async throws -> any QwenSpeechRecognizing {
        if let model { return model }
        await progress(.init(
            stage: .waitingForModel,
            fraction: 0,
            message: "Checking the local Qwen multilingual model"
        ))
        try FileManager.default.createDirectory(
            at: modelStorageURL,
            withIntermediateDirectories: true
        )
        let loaded = try await modelLoader(qwenModelID, modelStorageURL) { fraction, status in
            await progress(.init(
                stage: fraction < 0.8 ? .downloadingModel : .waitingForModel,
                fraction: fraction,
                message: Self.modelStatus(status, fraction: fraction)
            ))
        }
        model = loaded
        await progress(.init(
            stage: .waitingForModel,
            fraction: 1,
            message: "Qwen is warm and ready on this Mac"
        ))
        return loaded
    }

    private static func loadModel(
        modelID: String,
        storageURL: URL,
        progress: @escaping @Sendable (Double, String) async -> Void
    ) async throws -> any QwenSpeechRecognizing {
        try await Qwen3ASRModel.fromPretrained(
            modelId: modelID,
            cacheDir: storageURL,
            offlineMode: false
        ) { fraction, status in
            Task { await progress(fraction, status) }
        }
    }

    static func context(from phrases: [String], limit: Int = 80) -> String? {
        context(from: phrases, priorTranscript: "", limit: limit)
    }

    static func context(
        from phrases: [String],
        priorTranscript: String,
        limit: Int = 80,
        priorWordLimit: Int = 48
    ) -> String? {
        var seen = Set<String>()
        let normalized = phrases.compactMap { phrase -> String? in
            let value = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            let key = value.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            return seen.insert(key).inserted ? value : nil
        }.prefix(max(0, limit))
        var parts: [String] = []
        if !normalized.isEmpty {
            parts.append("Vocabulary and names: " + normalized.joined(separator: ", "))
        }
        let priorWords = priorTranscript.split(whereSeparator: \.isWhitespace)
        if priorWordLimit > 0, !priorWords.isEmpty {
            let tail = priorWords.suffix(priorWordLimit).joined(separator: " ")
            parts.append(
                "Prior transcript context — continue after this; do not repeat it: \(tail)"
            )
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    static func maximumTokens(for duration: TimeInterval) -> Int {
        min(448, max(64, Int(ceil(max(0, duration) * 18))))
    }

    static func spokenLanguageSummary(text: String, requested: String?) -> String? {
        let hasDevanagari = text.unicodeScalars.contains {
            (0x0900...0x097F).contains(Int($0.value))
        }
        let hasLatin = text.unicodeScalars.contains {
            (0x0041...0x005A).contains(Int($0.value))
                || (0x0061...0x007A).contains(Int($0.value))
        }
        if hasLatin && hasDevanagari { return "en + hi" }
        if hasDevanagari { return "hi" }
        if hasLatin { return requested == "hi" ? "hi + en" : "en" }
        return requested
    }

    private static func modelStatus(_ status: String, fraction: Double) -> String {
        if fraction < 0.8 { return "Downloading Qwen accuracy model locally" }
        let value = status.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Loading Qwen into unified memory" : value
    }
}
