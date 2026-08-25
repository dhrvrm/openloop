import ADHDCore
import Foundation

struct VoiceEvaluationReference: Codable, Equatable, Sendable {
    let id: String
    let audio: String
    let reference: String?
    let languages: [String]
    let condition: String?
    let domainTerms: [String]
    let languageHint: String?

    init(
        id: String,
        audio: String,
        reference: String? = nil,
        languages: [String] = [],
        condition: String? = nil,
        domainTerms: [String] = [],
        languageHint: String? = nil
    ) {
        self.id = id
        self.audio = audio
        self.reference = reference
        self.languages = languages
        self.condition = condition
        self.domainTerms = domainTerms
        self.languageHint = languageHint
    }

    enum CodingKeys: String, CodingKey {
        case id, audio, reference, languages, condition
        case domainTerms = "domain_terms"
        case languageHint = "language_hint"
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        audio = try values.decode(String.self, forKey: .audio)
        reference = try values.decodeIfPresent(String.self, forKey: .reference)
        languages = try values.decodeIfPresent([String].self, forKey: .languages) ?? []
        condition = try values.decodeIfPresent(String.self, forKey: .condition)
        domainTerms = try values.decodeIfPresent([String].self, forKey: .domainTerms) ?? []
        languageHint = try values.decodeIfPresent(String.self, forKey: .languageHint)
    }
}

struct VoiceEvaluationSegment: Codable, Equatable, Sendable {
    let speaker: String
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

struct VoiceEvaluationHypothesis: Codable, Equatable, Sendable {
    let id: String
    let hypothesis: String
    let languages: [String]
    let latencyMS: Double
    let coldStart: Bool
    let modelIdentifier: String
    let detectedLanguage: String?
    let segments: [VoiceEvaluationSegment]
    let error: String?

    enum CodingKeys: String, CodingKey {
        case id, hypothesis, languages, segments, error
        case latencyMS = "latency_ms"
        case coldStart = "cold_start"
        case modelIdentifier = "model_identifier"
        case detectedLanguage = "detected_language"
    }
}

enum VoiceEvaluationLanguageDetector {
    static func sequence(in text: String) -> [String] {
        var result: [String] = []
        for scalar in text.unicodeScalars {
            let language: String?
            switch scalar.value {
            case 0x0041...0x005A, 0x0061...0x007A, 0x00C0...0x024F:
                language = "en"
            case 0x0900...0x097F, 0xA8E0...0xA8FF:
                language = "hi"
            default:
                language = nil
            }
            if let language, result.last != language {
                result.append(language)
            }
        }
        return result
    }
}

struct VoiceEvaluationRunner: Sendable {
    let transcriber: any MeetingTranscribing

    func evaluate(
        _ references: [VoiceEvaluationReference],
        relativeTo baseURL: URL,
        languageCode: String?
    ) async -> [VoiceEvaluationHypothesis] {
        var rows: [VoiceEvaluationHypothesis] = []
        for (index, reference) in references.enumerated() {
            let audioURL = Self.audioURL(reference.audio, relativeTo: baseURL)
            let selectedLanguage = Self.normalizedLanguage(
                reference.languageHint ?? languageCode
            )
            let startedAt = ContinuousClock.now
            do {
                guard FileManager.default.fileExists(atPath: audioURL.path) else {
                    throw VoiceEvaluationError.missingAudio(audioURL.path)
                }
                let output = try await transcriber.transcribe(
                    audioURL: audioURL,
                    languageCode: selectedLanguage,
                    progress: { _ in }
                )
                let text = output.segments.map(\.text).joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                rows.append(VoiceEvaluationHypothesis(
                    id: reference.id,
                    hypothesis: text,
                    languages: VoiceEvaluationLanguageDetector.sequence(in: text),
                    latencyMS: Self.milliseconds(since: startedAt),
                    coldStart: index == 0,
                    modelIdentifier: output.modelIdentifier,
                    detectedLanguage: output.detectedLanguage,
                    segments: output.segments.map {
                        VoiceEvaluationSegment(
                            speaker: $0.speaker ?? "Speaker 1",
                            start: $0.start,
                            end: $0.end,
                            text: $0.text
                        )
                    },
                    error: nil
                ))
            } catch {
                rows.append(VoiceEvaluationHypothesis(
                    id: reference.id,
                    hypothesis: "",
                    languages: [],
                    latencyMS: Self.milliseconds(since: startedAt),
                    coldStart: index == 0,
                    modelIdentifier: transcriber.modelIdentifier,
                    detectedLanguage: nil,
                    segments: [],
                    error: String(describing: error)
                ))
            }
        }
        return rows
    }

    private static func audioURL(_ path: String, relativeTo baseURL: URL) -> URL {
        if NSString(string: path).isAbsolutePath {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return baseURL.appendingPathComponent(path).standardizedFileURL
    }

    private static func normalizedLanguage(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.lowercased() != "auto" else { return nil }
        return value
    }

    private static func milliseconds(
        since instant: ContinuousClock.Instant
    ) -> Double {
        let duration = instant.duration(to: .now)
        let components = duration.components
        return max(0, Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000)
    }
}

enum VoiceEvaluationError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case missingAudio(String)
    case duplicateID(String)

    var description: String {
        switch self {
        case let .invalidArguments(message): message
        case let .missingAudio(path): "missing audio: \(path)"
        case let .duplicateID(id): "duplicate manifest id: \(id)"
        }
    }
}

enum VoiceEvaluationEngine: String, CaseIterable, Sendable {
    case dictation
    case meeting
    case qwen
    case whisper
}

struct VoiceEvaluationCommand: Sendable {
    let manifestURL: URL
    let outputURL: URL
    let dataDirectory: URL
    let engine: VoiceEvaluationEngine
    let languageCode: String?

    static func isRequested(_ arguments: [String]) -> Bool {
        arguments.contains("--voice-eval")
    }

    init(
        arguments: [String],
        currentDirectory: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
    ) throws {
        guard Self.isRequested(arguments) else {
            throw VoiceEvaluationError.invalidArguments("missing --voice-eval")
        }
        var values: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--voice-eval" {
                index += 1
                continue
            }
            guard argument.hasPrefix("--"), index + 1 < arguments.count else {
                throw VoiceEvaluationError.invalidArguments(
                    "expected a value after \(argument)"
                )
            }
            values[argument] = arguments[index + 1]
            index += 2
        }
        guard let manifest = values["--manifest"], !manifest.isEmpty else {
            throw VoiceEvaluationError.invalidArguments("--manifest is required")
        }
        guard let output = values["--output"], !output.isEmpty else {
            throw VoiceEvaluationError.invalidArguments("--output is required")
        }
        let engineName = values["--engine"] ?? VoiceEvaluationEngine.dictation.rawValue
        guard let engine = VoiceEvaluationEngine(rawValue: engineName) else {
            throw VoiceEvaluationError.invalidArguments(
                "--engine must be \(VoiceEvaluationEngine.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }
        let defaultDataDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/OpenLoopADHD",
                isDirectory: true
            )
        manifestURL = Self.resolvedURL(manifest, relativeTo: currentDirectory)
        outputURL = Self.resolvedURL(output, relativeTo: currentDirectory)
        dataDirectory = values["--data-directory"].map {
            Self.resolvedURL($0, relativeTo: currentDirectory)
        } ?? defaultDataDirectory
        self.engine = engine
        let language = values["--language"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        languageCode = language?.isEmpty == false && language?.lowercased() != "auto"
            ? language
            : nil
    }

    func run() async -> Int32 {
        do {
            let references = try Self.readManifest(manifestURL)
            let vocabulary = Array(Set(references.flatMap(\.domainTerms))).sorted()
            let transcriber = makeTranscriber(vocabulary: vocabulary)
            let rows = await VoiceEvaluationRunner(transcriber: transcriber).evaluate(
                references,
                relativeTo: URL(
                    fileURLWithPath: FileManager.default.currentDirectoryPath,
                    isDirectory: true
                ),
                languageCode: languageCode
            )
            try Self.write(rows, to: outputURL)
            let failures = rows.filter { $0.error != nil }.count
            print("voice-eval-cases=\(rows.count)")
            print("voice-eval-failures=\(failures)")
            print("voice-eval-output=\(outputURL.path)")
            return failures == 0 ? EXIT_SUCCESS : 2
        } catch {
            FileHandle.standardError.write(Data("voice-eval-error: \(error)\n".utf8))
            return EXIT_FAILURE
        }
    }

    private func makeTranscriber(vocabulary: [String]) -> any MeetingTranscribing {
        let whisper = WhisperKitMeetingTranscriber(
            modelStorageURL: dataDirectory.appendingPathComponent(
                "Models/WhisperKit",
                isDirectory: true
            )
        )
        let qwen = QwenMeetingTranscriber(
            modelStorageURL: dataDirectory.appendingPathComponent(
                "Models/Qwen3-ASR-1.7B-8bit",
                isDirectory: true
            ),
            fallback: whisper,
            fallbackEnabled: false,
            contextProvider: { vocabulary }
        )
        switch engine {
        case .qwen:
            return qwen
        case .whisper:
            return whisper
        case .dictation:
            return AccuracyFirstTranscriber(
                primary: qwen,
                witness: whisper,
                expectedDomainTerms: { vocabulary }
            )
        case .meeting:
            return AccuracyFirstTranscriber(
                primary: whisper,
                witness: qwen,
                expectedDomainTerms: { vocabulary }
            )
        }
    }

    private static func readManifest(_ url: URL) throws -> [VoiceEvaluationReference] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        var seen: Set<String> = []
        return try contents.split(whereSeparator: \.isNewline).enumerated().compactMap {
            lineNumber, line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
            let row: VoiceEvaluationReference
            do {
                row = try decoder.decode(
                    VoiceEvaluationReference.self,
                    from: Data(trimmed.utf8)
                )
            } catch {
                throw VoiceEvaluationError.invalidArguments(
                    "\(url.path):\(lineNumber + 1): \(error)"
                )
            }
            guard !row.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VoiceEvaluationError.invalidArguments(
                    "\(url.path):\(lineNumber + 1): id is required"
                )
            }
            guard seen.insert(row.id).inserted else {
                throw VoiceEvaluationError.duplicateID(row.id)
            }
            return row
        }
    }

    private static func write(
        _ rows: [VoiceEvaluationHypothesis],
        to url: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try rows.reduce(into: Data()) { output, row in
            output.append(try encoder.encode(row))
            output.append(Data([0x0A]))
        }
        try data.write(to: url, options: .atomic)
    }

    private static func resolvedURL(_ path: String, relativeTo baseURL: URL) -> URL {
        if NSString(string: path).isAbsolutePath {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return baseURL.appendingPathComponent(path).standardizedFileURL
    }
}

private final class VoiceEvaluationCommandLatch: @unchecked Sendable {
    private let condition = NSCondition()
    private var result: Int32?

    func finish(_ result: Int32) {
        condition.lock()
        self.result = result
        condition.broadcast()
        condition.unlock()
    }

    func wait() -> Int32 {
        condition.lock()
        while result == nil { condition.wait() }
        let value = result ?? EXIT_FAILURE
        condition.unlock()
        return value
    }
}

enum VoiceEvaluationCommandExecutor {
    static func execute(_ command: VoiceEvaluationCommand) -> Never {
        let latch = VoiceEvaluationCommandLatch()
        Task.detached {
            latch.finish(await command.run())
        }
        exit(latch.wait())
    }
}
