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
    private var whisperKit: WhisperKit?
    private var speakerKit: SpeakerKit?

    init(
        modelIdentifier: String = "large-v3-v20240930_626MB",
        modelStorageURL: URL,
        speakerDiarizationEnabled: Bool = true
    ) {
        self.modelIdentifier = modelIdentifier
        self.modelStorageURL = modelStorageURL
        self.speakerDiarizationEnabled = speakerDiarizationEnabled
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

        let callbackGate = TranscriptionAttemptGate()

        let options = Self.decodingOptions(languageCode: languageCode)
        let windows: [TranscriptionResult]
        if languageCode == nil, duration > 0, duration <= 45 {
            let audio = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
            let ranges = UtteranceAudioChunker.ranges(in: audio)
            let chunks = try await plannedAutomaticChunks(
                audio: audio,
                speechRanges: ranges,
                pipeline: pipeline,
                progress: progress
            )
            if chunks.count > 1 {
                do {
                    let utteranceBatches = try await transcribeUtterances(
                        audio: audio,
                        chunks: chunks,
                        pipeline: pipeline,
                        options: options,
                        progress: progress
                    )
                    if Self.allUtterancesHaveUsableTranscript(utteranceBatches) {
                        windows = utteranceBatches.flatMap { $0 }
                    } else {
                        await progress(.init(
                            stage: .transcribing,
                            fraction: 0.1,
                            message: "Rechecking the complete recording locally"
                        ))
                        windows = try await transcribeFile(
                            audioURL: audioURL,
                            pipeline: pipeline,
                            options: options,
                            duration: duration,
                            progress: progress,
                            callbackGate: callbackGate
                        )
                    }
                } catch {
                    if Task.isCancelled { throw CancellationError() }
                    await progress(.init(
                        stage: .transcribing,
                        fraction: 0.1,
                        message: "A language chunk failed; rechecking the complete recording locally"
                    ))
                    windows = try await transcribeFile(
                        audioURL: audioURL,
                        pipeline: pipeline,
                        options: options,
                        duration: duration,
                        progress: progress,
                        callbackGate: callbackGate
                    )
                }
            } else {
                windows = try await transcribeFile(
                    audioURL: audioURL,
                    pipeline: pipeline,
                    options: options,
                    duration: duration,
                    progress: progress,
                    callbackGate: callbackGate
                )
            }
        } else {
            windows = try await transcribeFile(
                audioURL: audioURL,
                pipeline: pipeline,
                options: options,
                duration: duration,
                progress: progress,
                callbackGate: callbackGate
            )
        }
        await callbackGate.invalidateAndDrain()
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
            detectedLanguage: Self.spokenLanguageSummary(
                modelLanguage: mapped.language,
                segments: mapped.segments
            ),
            modelIdentifier: modelIdentifier,
            segments: mapped.segments
        )
    }

    private func plannedAutomaticChunks(
        audio: [Float],
        speechRanges: [Range<Int>],
        pipeline: WhisperKit,
        progress: @escaping @Sendable (MeetingTranscriptionProgress) async -> Void
    ) async throws -> [PlannedAudioChunk] {
        guard !speechRanges.isEmpty else { return [] }
        let probeRanges = CodeSwitchChunkPlanner.probeRanges(
            speechRanges: speechRanges,
            audioCount: audio.count,
            sampleRate: WhisperKit.sampleRate
        )
        var probes: [LanguageProbe] = []
        if !probeRanges.isEmpty {
            await progress(.init(
                stage: .preparingAudio,
                fraction: 1,
                message: "Checking for language changes locally"
            ))
        }
        for range in probeRanges {
            try Task.checkCancellation()
            guard let detection = try? await pipeline.detectLangauge(audioArray: Array(audio[range])) else {
                continue
            }
            probes.append(LanguageProbe(
                center: range.lowerBound + range.count / 2,
                language: detection.language,
                confidenceMargin: Self.languageConfidenceMargin(detection.langProbs)
            ))
        }
        if !probes.isEmpty {
            let scan = probes.map {
                "\($0.language.lowercased()) \(Int(($0.confidenceMargin * 100).rounded()))%"
            }.joined(separator: " · ")
            await progress(.init(
                stage: .preparingAudio,
                fraction: 1,
                message: "Language scan: \(scan)"
            ))
        }
        let chunks = CodeSwitchChunkPlanner.plan(
            audio: audio,
            speechRanges: speechRanges,
            probes: probes,
            sampleRate: WhisperKit.sampleRate
        )
        if chunks.count > 1 {
            let boundaries = chunks.dropLast().map {
                String(format: "%.1fs", Double($0.coreRange.upperBound) / Double(WhisperKit.sampleRate))
            }.joined(separator: ", ")
            await progress(.init(
                stage: .preparingAudio,
                fraction: 1,
                message: "Language change found near \(boundaries)"
            ))
        }
        return chunks
    }

    private func transcribeFile(
        audioURL: URL,
        pipeline: WhisperKit,
        options: DecodingOptions,
        duration: TimeInterval,
        progress: @escaping @Sendable (MeetingTranscriptionProgress) async -> Void,
        callbackGate: TranscriptionAttemptGate
    ) async throws -> [TranscriptionResult] {
        let attempt = callbackGate.beginAttempt()
        let callback: TranscriptionCallback = { update in
            guard callbackGate.isCurrent(attempt) else { return false }
            let estimated = Self.estimatedFraction(
                windowID: update.windowId,
                inputAudioSeconds: update.timings.inputAudioSeconds,
                duration: duration
            )
            let presentation = MeetingTranscriptionProgress(
                stage: .transcribing,
                fraction: estimated,
                message: update.text.nilIfBlank == nil
                    ? "Listening across the meeting"
                    : "Transcribing locally",
                previewText: update.text
            )
            let scheduled = callbackGate.schedule(attempt: attempt) {
                await progress(presentation)
            }
            return scheduled && !Task.isCancelled
        }
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
        chunks: [PlannedAudioChunk],
        pipeline: WhisperKit,
        options: DecodingOptions,
        progress: @escaping @Sendable (MeetingTranscriptionProgress) async -> Void
    ) async throws -> [[TranscriptionResult]] {
        var batches: [[TranscriptionResult]] = []
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            let coreAudio = Array(audio[chunk.coreRange])
            let chunkLanguage = try? await pipeline.detectLangauge(audioArray: coreAudio).language
            let chunkOptions = chunkLanguage.map(Self.decodingOptions(languageCode:)) ?? options
            let transcriptionRange = chunkLanguage == nil
                ? chunk.decodeRange
                : Self.isolatedDecodeRange(
                    coreRange: chunk.coreRange,
                    audioCount: audio.count,
                    sampleRate: WhisperKit.sampleRate
                )
            let results = try await pipeline.transcribe(
                audioArray: Array(audio[transcriptionRange]),
                audioArrayOffset: transcriptionRange.lowerBound,
                decodeOptions: chunkOptions
            )
            let seekTime = Float(transcriptionRange.lowerBound) / Float(WhisperKit.sampleRate)
            for result in results {
                result.seekTime = seekTime
                let absolute = result.segments.map {
                    TranscriptionUtilities.updateSegmentTimings(
                        segment: $0,
                        seekOffsetIndex: transcriptionRange.lowerBound
                    )
                }
                result.segments = Self.trim(
                    absolute,
                    to: chunk.coreRange,
                    leadingContextLanguage: result.language
                )
                result.text = result.segments.map(\.text).joined(separator: " ")
            }
            batches.append(results)
            let preview = batches
                .flatMap { $0 }
                .flatMap(\.segments)
                .map(\.text)
                .joined(separator: " ")
            await progress(.init(
                stage: .transcribing,
                fraction: min(0.98, Double(index + 1) / Double(chunks.count)),
                message: "Detecting each spoken language locally",
                previewText: preview
            ))
        }
        return Self.deduplicateBoundaryWords(batches, chunks: chunks)
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

    static func spokenLanguageSummary(
        modelLanguage: String?,
        segments: [TranscriptSegment]
    ) -> String? {
        var scriptOrder: [String] = []
        var seen = Set<String>()
        for scalar in segments.flatMap({ Array($0.text.unicodeScalars) }) {
            let language: String?
            switch scalar.value {
            case 0x0041...0x005A, 0x0061...0x007A: language = "en"
            case 0x0900...0x097F: language = "hi"
            default: language = nil
            }
            if let language, seen.insert(language).inserted { scriptOrder.append(language) }
        }

        let containsHindi = scriptOrder.contains("hi")
        let modelLanguages = modelLanguage?
            .components(separatedBy: " + ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            ?? []
        if containsHindi {
            return languageSummary(scriptOrder + modelLanguages)
        }
        return languageSummary(modelLanguages)
    }

    static func hasUsableTranscript(_ results: [TranscriptionResult]) -> Bool {
        results.contains { result in
            result.segments.contains { segment in
                segment.text.nilIfBlank != nil && segment.end >= segment.start
            }
        }
    }

    static func allUtterancesHaveUsableTranscript(
        _ batches: [[TranscriptionResult]]
    ) -> Bool {
        !batches.isEmpty && batches.allSatisfy(hasUsableTranscript)
    }

    static func decodingOptions(languageCode: String?) -> DecodingOptions {
        DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: languageCode,
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: languageCode == nil,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: true,
            promptTokens: nil,
            concurrentWorkerCount: 4
        )
    }

    static func isolatedDecodeRange(
        coreRange: Range<Int>,
        audioCount: Int,
        sampleRate: Int,
        context: TimeInterval = 0.2
    ) -> Range<Int> {
        let contextSamples = max(0, Int(context * Double(sampleRate)))
        let lowerBound = max(0, coreRange.lowerBound - contextSamples)
        let upperBound = min(audioCount, coreRange.upperBound + contextSamples)
        return lowerBound..<upperBound
    }

    static func languageConfidenceMargin(_ probabilities: [String: Float]) -> Float {
        let values = probabilities.values.sorted(by: >)
        guard let first = values.first else { return 0 }
        guard values.count > 1 else { return 1 }
        return max(0, first - values[1])
    }

    static func trim(
        _ segments: [TranscriptionSegment],
        to coreRange: Range<Int>,
        leadingContextLanguage: String? = nil
    ) -> [TranscriptionSegment] {
        return segments.compactMap { source -> TranscriptionSegment? in
            var segment = source
            if let words = segment.words, !words.isEmpty {
                let retained = words.filter { word in
                    let midpoint = (word.start + word.end) / 2
                    let sample = Int(midpoint * Float(WhisperKit.sampleRate))
                    if coreRange.contains(sample) { return true }
                    guard sample < coreRange.lowerBound else { return false }
                    return wordMatchesScript(word.word, language: leadingContextLanguage)
                }
                guard let first = retained.first, let last = retained.last else { return nil }
                segment.words = retained
                segment.start = first.start
                segment.end = last.end
                segment.text = retained.map(\.word).joined()
                return segment.text.nilIfBlank == nil ? nil : segment
            }
            let midpoint = (segment.start + segment.end) / 2
            return coreRange.contains(Int(midpoint * Float(WhisperKit.sampleRate)))
                ? segment
                : nil
        }
    }

    static func deduplicateBoundaryWords(
        _ batches: [[TranscriptionResult]],
        chunks: [PlannedAudioChunk]
    ) -> [[TranscriptionResult]] {
        var priorWords: [(text: String, start: Float, end: Float)] = []
        for (batchIndex, batch) in batches.enumerated() {
            let coreLowerBound = chunks.indices.contains(batchIndex)
                ? chunks[batchIndex].coreRange.lowerBound
                : 0
            var acceptedInBatch: [(text: String, start: Float, end: Float)] = []
            for result in batch {
                result.segments = result.segments.compactMap { source in
                    guard let words = source.words, !words.isEmpty else { return source }
                    let retained = words.filter { word in
                        let text = normalizedBoundaryWord(word.word)
                        let midpoint = (word.start + word.end) / 2
                        let isLeadingContext = Int(midpoint * Float(WhisperKit.sampleRate))
                            < coreLowerBound
                        let duplicate = isLeadingContext && !text.isEmpty && priorWords.contains {
                            $0.text == text
                                && max($0.start, word.start) <= min($0.end, word.end) + 0.2
                        }
                        if !duplicate { acceptedInBatch.append((text, word.start, word.end)) }
                        return !duplicate
                    }
                    guard let first = retained.first, let last = retained.last else { return nil }
                    var segment = source
                    segment.words = retained
                    segment.start = first.start
                    segment.end = last.end
                    segment.text = retained.map(\.word).joined()
                    return segment.text.nilIfBlank == nil ? nil : segment
                }
                result.text = result.segments.map(\.text).joined(separator: " ")
            }
            priorWords.append(contentsOf: acceptedInBatch)
        }
        return batches
    }

    private static func wordMatchesScript(_ word: String, language: String?) -> Bool {
        switch language?.lowercased() {
        case "hi":
            return word.unicodeScalars.contains { (0x0900...0x097F).contains($0.value) }
        case "en":
            return word.unicodeScalars.contains {
                (0x0041...0x005A).contains($0.value) || (0x0061...0x007A).contains($0.value)
            }
        default:
            return false
        }
    }

    private static func normalizedBoundaryWord(_ word: String) -> String {
        String(word.lowercased().unicodeScalars.filter {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
        })
    }

    private static func audioDuration(_ url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return 0 }
        let seconds = duration.seconds
        return seconds.isFinite ? max(0, seconds) : 0
    }
}

final class TranscriptionAttemptGate: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    private var deliveries: [Task<Void, Never>] = []

    func beginAttempt() -> Int {
        lock.lock()
        defer { lock.unlock() }
        generation += 1
        return generation
    }

    func schedule(
        attempt: Int,
        operation: @escaping @Sendable () async -> Void
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard attempt == generation else { return false }
        let delivery = Task {
            guard self.isCurrent(attempt) else { return }
            await operation()
        }
        deliveries.append(delivery)
        return true
    }

    func invalidateAndDrain() async {
        let pending = invalidateAndTakeDeliveries()
        for delivery in pending {
            await delivery.value
        }
    }

    private func invalidateAndTakeDeliveries() -> [Task<Void, Never>] {
        lock.lock()
        defer { lock.unlock() }
        generation += 1
        let pending = deliveries
        deliveries.removeAll(keepingCapacity: true)
        return pending
    }

    func invalidateForTesting() {
        let pending = invalidateAndTakeDeliveries()
        for delivery in pending {
            delivery.cancel()
        }
    }

    func isCurrent(_ attempt: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return attempt == generation
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
