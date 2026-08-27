import ADHDCore
import AVFoundation
import CryptoKit
import Foundation
import SpeakerKit
import WhisperKit

enum WhisperCppTranscriptionError: Error, CustomStringConvertible {
    case executableMissing
    case modelDownloadFailed
    case modelChecksumMismatch
    case processFailed(Int32, String)
    case invalidOutput

    var description: String {
        switch self {
        case .executableMissing: "The bundled high-accuracy speech engine is missing."
        case .modelDownloadFailed: "The full local speech model could not be downloaded."
        case .modelChecksumMismatch: "The downloaded speech model failed its integrity check."
        case let .processFailed(status, message):
            "The high-accuracy speech engine exited with status \(status): \(message)"
        case .invalidOutput: "The high-accuracy speech engine returned invalid output."
        }
    }
}

private final class WhisperProcessBox: @unchecked Sendable {
    let process = Process()
}

actor WhisperCppModelStore {
    static let modelFileName = "ggml-large-v3.bin"
    static let modelByteCount: Int64 = 3_095_033_483
    static let modelSHA256 = "64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2"
    static let modelURL = URL(
        string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin"
    )!

    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    func isCached() -> Bool {
        let modelURL = directory.appendingPathComponent(Self.modelFileName)
        let markerURL = directory.appendingPathComponent("\(Self.modelFileName).sha256")
        return Self.isTrustedModel(modelURL, markerURL: markerURL)
    }

    func resolve(
        progress: @escaping @Sendable (MeetingTranscriptionProgress) async -> Void
    ) async throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let modelURL = directory.appendingPathComponent(Self.modelFileName)
        let markerURL = directory.appendingPathComponent("\(Self.modelFileName).sha256")
        if Self.isTrustedModel(modelURL, markerURL: markerURL) { return modelURL }

        await progress(.init(
            stage: .downloadingModel,
            fraction: 0,
            message: "Downloading the 3.1 GB full multilingual model once"
        ))
        let temporaryURL: URL
        do {
            let response: URLResponse
            (temporaryURL, response) = try await URLSession.shared.download(from: Self.modelURL)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw WhisperCppTranscriptionError.modelDownloadFailed
            }
        } catch {
            throw WhisperCppTranscriptionError.modelDownloadFailed
        }

        await progress(.init(
            stage: .waitingForModel,
            fraction: 0.9,
            message: "Checking the downloaded accuracy model"
        ))
        guard try Self.sha256(of: temporaryURL) == Self.modelSHA256 else {
            throw WhisperCppTranscriptionError.modelChecksumMismatch
        }
        if manager.fileExists(atPath: modelURL.path) {
            try manager.removeItem(at: modelURL)
        }
        try manager.moveItem(at: temporaryURL, to: modelURL)
        try Self.modelSHA256.write(to: markerURL, atomically: true, encoding: .utf8)
        return modelURL
    }

    static func isTrustedModel(_ modelURL: URL, markerURL: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: modelURL.path),
              let size = attributes[.size] as? NSNumber,
              size.int64Value == modelByteCount,
              let marker = try? String(contentsOf: markerURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        else { return false }
        return marker == modelSHA256
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while true {
            let data = try handle.read(upToCount: 4 * 1_024 * 1_024) ?? Data()
            if data.isEmpty { break }
            digest.update(data: data)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

actor WhisperCppMeetingTranscriber: MeetingTranscribing {
    static let engineVersion = "whisper.cpp b4938 · full large-v3"

    nonisolated let modelIdentifier = engineVersion
    private let executableURL: URL?
    private let modelStore: WhisperCppModelStore
    private let speakerDiarizationEnabled: Bool
    private let contextProvider: @Sendable () async -> [String]
    private var speakerKit: SpeakerKit?

    init(
        modelStorageURL: URL,
        executableURL: URL? = WhisperCppMeetingTranscriber.bundledExecutableURL(),
        speakerDiarizationEnabled: Bool = true,
        contextProvider: @escaping @Sendable () async -> [String] = { [] }
    ) {
        self.executableURL = executableURL
        modelStore = WhisperCppModelStore(directory: modelStorageURL)
        self.speakerDiarizationEnabled = speakerDiarizationEnabled
        self.contextProvider = contextProvider
    }

    static func bundledExecutableURL(bundle: Bundle = .main) -> URL? {
        let candidate = bundle.resourceURL?
            .appendingPathComponent("Transcription", isDirectory: true)
            .appendingPathComponent("whisper-cli", isDirectory: false)
        guard let candidate,
              FileManager.default.isExecutableFile(atPath: candidate.path) else { return nil }
        return candidate
    }

    func diagnostics() async -> MeetingEngineDiagnostics {
        let cached = await modelStore.isCached()
        return MeetingEngineDiagnostics(
            transcriptionModel: modelIdentifier,
            diarizationModel: "SpeakerKit Pyannote",
            transcriptionModelState: cached ? .cached : .downloadRequired,
            modelCacheLocation: "OpenLoop data / Models / WhisperCpp",
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
        guard let executableURL,
              FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw WhisperCppTranscriptionError.executableMissing
        }
        let modelURL = try await modelStore.resolve(progress: progress)
        let audio = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
        guard !audio.isEmpty else { throw MeetingTranscriptionError.emptyTranscript }

        await progress(.init(
            stage: .preparingAudio,
            fraction: 1,
            message: "Preparing the original audio for the accuracy pass"
        ))
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenLoop-Whisper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let waveURL = workspace.appendingPathComponent("input.wav")
        try Self.writeWave(samples: audio, to: waveURL)
        let outputPrefix = workspace.appendingPathComponent("transcript")
        let vocabulary = await contextProvider()

        await progress(.init(
            stage: .transcribing,
            fraction: 0.05,
            message: "Running the full multilingual accuracy pass"
        ))
        let document = try await Self.run(
            executableURL: executableURL,
            modelURL: modelURL,
            audioURL: waveURL,
            outputPrefix: outputPrefix,
            languageCode: languageCode,
            prompt: Self.prompt(from: vocabulary)
        )
        var segments = try document.transcription.compactMap { item -> TranscriptSegment? in
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, item.offsets.to >= item.offsets.from else { return nil }
            return try TranscriptSegment(
                start: Double(item.offsets.from) / 1_000,
                end: Double(item.offsets.to) / 1_000,
                text: text
            )
        }
        guard !segments.isEmpty else { throw MeetingTranscriptionError.emptyTranscript }

        var separation = SpeakerSeparationState.notRequested
        var fingerprints: [LocalSpeakerFingerprint] = []
        if speakerDiarizationEnabled {
            do {
                let result = try await diarize(audio: audio, progress: progress)
                segments = try Self.segmentsWithSpeakers(document, diarization: result)
                separation = .complete(speakerCount: result.speakerCount)
                fingerprints = result.speakerCentroidEmbeddings.keys.sorted().compactMap { id in
                    guard let embedding = result.speakerCentroidEmbeddings[id], !embedding.isEmpty else {
                        return nil
                    }
                    return LocalSpeakerFingerprint(
                        localSpeakerLabel: WhisperKitMeetingTranscriber.speakerLabel(id),
                        embedding: embedding
                    )
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                separation = .unavailable
            }
        }

        await progress(.init(
            stage: .transcribing,
            fraction: 1,
            message: "Full multilingual transcript ready",
            previewText: segments.map(\.text).joined(separator: " ")
        ))
        return LocalTranscriptionOutput(
            duration: Double(audio.count) / Double(WhisperKit.sampleRate),
            detectedLanguage: WhisperKitMeetingTranscriber.spokenLanguageSummary(
                modelLanguage: document.result.language,
                segments: segments
            ),
            modelIdentifier: modelIdentifier,
            segments: segments,
            speakerSeparation: separation,
            speakerFingerprints: fingerprints
        )
    }

    private func diarize(
        audio: [Float],
        progress: @escaping @Sendable (MeetingTranscriptionProgress) async -> Void
    ) async throws -> DiarizationResult {
        await progress(.init(stage: .diarizing, fraction: 0, message: "Separating speakers locally"))
        let engine: SpeakerKit
        if let speakerKit {
            engine = speakerKit
        } else {
            let loaded = try await SpeakerKit(PyannoteConfig(download: true, load: true, verbose: false))
            speakerKit = loaded
            engine = loaded
        }
        return try await engine.diarize(audioArray: audio) { value in
            Task {
                await progress(.init(
                    stage: .diarizing,
                    fraction: value.fractionCompleted,
                    message: "Separating speakers locally"
                ))
            }
        }
    }

    static func segmentsWithSpeakers(
        _ document: WhisperCppDocument,
        diarization: DiarizationResult
    ) throws -> [TranscriptSegment] {
        struct Word {
            let item: Int
            var text: String
            var start: Double
            var end: Double
        }
        var words: [Word] = []
        for (itemIndex, item) in document.transcription.enumerated() {
            let itemWordStart = words.count
            var current: Word?
            for token in item.tokens ?? [] where !token.text.hasPrefix("[_") {
                let startsWord = token.text.first?.isWhitespace == true
                if startsWord, let value = current {
                    words.append(value)
                    current = nil
                }
                if current == nil {
                    current = Word(
                        item: itemIndex,
                        text: token.text,
                        start: Double(token.offsets.from) / 1_000,
                        end: Double(token.offsets.to) / 1_000
                    )
                } else {
                    current?.text += token.text
                    current?.end = Double(token.offsets.to) / 1_000
                }
            }
            if let current { words.append(current) }
            if words.count == itemWordStart {
                words.append(Word(
                    item: itemIndex,
                    text: item.text,
                    start: Double(item.offsets.from) / 1_000,
                    end: Double(item.offsets.to) / 1_000
                ))
            }
        }
        guard !words.isEmpty else { throw MeetingTranscriptionError.emptyTranscript }

        var output: [TranscriptSegment] = []
        var currentItem: Int?
        var currentSpeaker: Int?
        var currentText = ""
        var currentStart: Double = 0
        var currentEnd: Double = 0

        func flush() throws {
            let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            output.append(try TranscriptSegment(
                start: currentStart,
                end: currentEnd,
                text: text,
                speaker: currentSpeaker.map(WhisperKitMeetingTranscriber.speakerLabel)
            ))
        }

        for word in words {
            let speaker = bestSpeaker(
                start: word.start,
                end: word.end,
                diarization: diarization
            ) ?? currentSpeaker
            if currentItem != nil,
               (currentItem != word.item || currentSpeaker != speaker) {
                try flush()
                currentText = ""
            }
            if currentText.isEmpty { currentStart = word.start }
            currentItem = word.item
            currentSpeaker = speaker
            currentText += word.text
            currentEnd = word.end
        }
        try flush()
        return output
    }

    private static func bestSpeaker(
        start: Double,
        end: Double,
        diarization: DiarizationResult
    ) -> Int? {
        diarization.segments.max { lhs, rhs in
            speakerOverlap(start: start, end: end, lhs)
                < speakerOverlap(start: start, end: end, rhs)
        }.flatMap {
            speakerOverlap(start: start, end: end, $0) > 0 ? $0.speaker.speakerId : nil
        }
    }

    private static func speakerOverlap(
        start: Double,
        end: Double,
        _ speaker: SpeakerSegment
    ) -> Double {
        max(0, min(end, Double(speaker.endTime)) - max(start, Double(speaker.startTime)))
    }

    static func writeWave(samples: [Float], to url: URL) throws {
        let bytesPerSample = 2
        let dataByteCount = samples.count * bytesPerSample
        var data = Data()
        data.reserveCapacity(44 + dataByteCount)
        data.append(contentsOf: "RIFF".utf8)
        append(UInt32(36 + dataByteCount), to: &data)
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data)
        append(UInt16(1), to: &data)
        append(UInt32(WhisperKit.sampleRate), to: &data)
        append(UInt32(WhisperKit.sampleRate * bytesPerSample), to: &data)
        append(UInt16(bytesPerSample), to: &data)
        append(UInt16(16), to: &data)
        data.append(contentsOf: "data".utf8)
        append(UInt32(dataByteCount), to: &data)
        for sample in samples {
            let scaled = Int16((min(1, max(-1, sample)) * Float(Int16.max)).rounded())
            append(UInt16(bitPattern: scaled), to: &data)
        }
        try data.write(to: url, options: .atomic)
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    static func run(
        executableURL: URL,
        modelURL: URL,
        audioURL: URL,
        outputPrefix: URL,
        languageCode: String?,
        prompt: String? = nil
    ) async throws -> WhisperCppDocument {
        let box = WhisperProcessBox()
        let process = box.process
        process.executableURL = executableURL
        var arguments = [
            "-m", modelURL.path,
            "-f", audioURL.path,
            "-l", languageCode ?? "auto",
            "-bs", "8",
            "-bo", "8",
            "-ml", "50",
            "-sow",
            "-ojf",
            "-of", outputPrefix.path,
            "-np",
        ]
        if let prompt, !prompt.isEmpty {
            arguments.append(contentsOf: ["--prompt", prompt])
        }
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        let errorURL = outputPrefix.deletingLastPathComponent()
            .appendingPathComponent("whisper-stderr.log")
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        process.standardError = errorHandle
        try process.run()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    box.process.waitUntilExit()
                    continuation.resume()
                }
            }
        } onCancel: {
            if box.process.isRunning { box.process.terminate() }
        }
        try errorHandle.close()
        try Task.checkCancellation()
        let errorData = (try? Data(contentsOf: errorURL)) ?? Data()
        let errorText = String(data: errorData, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw WhisperCppTranscriptionError.processFailed(
                process.terminationStatus,
                String(errorText.suffix(1_000))
            )
        }
        let outputURL = outputPrefix.appendingPathExtension("json")
        guard let document = try? JSONDecoder().decode(
            WhisperCppDocument.self,
            from: Data(contentsOf: outputURL)
        ) else { throw WhisperCppTranscriptionError.invalidOutput }
        return document
    }

    static func prompt(from vocabulary: [String], limit: Int = 80) -> String? {
        var seen = Set<String>()
        let terms = vocabulary.compactMap { raw -> String? in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            let key = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return seen.insert(key).inserted ? value : nil
        }
        guard !terms.isEmpty else { return nil }
        return "Vocabulary and names: " + terms.prefix(limit).joined(separator: ", ")
    }
}

struct WhisperCppDocument: Decodable, Equatable, Sendable {
    struct Result: Decodable, Equatable, Sendable { let language: String }
    struct Item: Decodable, Equatable, Sendable {
        struct Offsets: Decodable, Equatable, Sendable { let from: Int; let to: Int }
        struct Token: Decodable, Equatable, Sendable {
            let text: String
            let offsets: Offsets
        }
        let text: String
        let offsets: Offsets
        let tokens: [Token]?
    }

    let result: Result
    let transcription: [Item]
}
