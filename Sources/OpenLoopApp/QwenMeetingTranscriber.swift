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
actor QwenMeetingTranscriber: MeetingTranscribing {
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
    private var model: (any QwenSpeechRecognizing)?

    init(
        qwenModelID: String = ASRModelSize.small.defaultModelId,
        modelStorageURL: URL,
        fallback: any MeetingTranscribing,
        fallbackEnabled: Bool = true,
        contextProvider: @escaping @Sendable () async -> [String] = { [] },
        modelLoader: ModelLoader? = nil
    ) {
        self.qwenModelID = qwenModelID
        self.modelIdentifier = "\(qwenModelID.split(separator: "/").last.map(String.init) ?? qwenModelID) · Whisper fallback"
        self.modelStorageURL = modelStorageURL
        self.fallback = fallback
        self.fallbackEnabled = fallbackEnabled
        self.contextProvider = contextProvider
        self.modelLoader = modelLoader ?? Self.loadModel
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
        let audio = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
        guard !audio.isEmpty else { throw MeetingTranscriptionError.emptyTranscript }
        let duration = Double(audio.count) / Double(WhisperKit.sampleRate)
        let vocabulary = await contextProvider()
        let context = Self.context(from: vocabulary)

        await progress(.init(
            stage: .transcribing,
            fraction: 0.08,
            message: "Recognizing Hindi and English with Qwen"
        ))
        let text = model.transcribe(
            audio: audio,
            sampleRate: WhisperKit.sampleRate,
            language: languageCode,
            maxTokens: Self.maximumTokens(for: duration),
            context: context
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        try Task.checkCancellation()
        guard !text.isEmpty else { throw MeetingTranscriptionError.emptyTranscript }

        let segment = try TranscriptSegment(start: 0, end: duration, text: text)
        let language = Self.spokenLanguageSummary(text: text, requested: languageCode)
        await progress(.init(
            stage: .transcribing,
            fraction: 1,
            message: "Qwen transcription complete",
            previewText: text
        ))
        return LocalTranscriptionOutput(
            duration: duration,
            detectedLanguage: language,
            modelIdentifier: qwenModelID,
            segments: [segment]
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
        guard !normalized.isEmpty else { return nil }
        return "Vocabulary and names: " + normalized.joined(separator: ", ")
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
