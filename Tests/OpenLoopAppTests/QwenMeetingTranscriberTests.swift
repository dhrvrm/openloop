import ADHDCore
import Foundation
import Testing
@testable import OpenLoopApp

@Test func qwenAccuracyProfileUsesTheLargestSupportedLocalASR() {
    #expect(QwenMeetingTranscriber.accuracyModelID == "aufklarer/Qwen3-ASR-1.7B-MLX-8bit")
    #expect(QwenMeetingTranscriber.accuracyModelID.contains("1.7B"))
    #expect(QwenMeetingTranscriber.streamingModelID == "aufklarer/Qwen3-ASR-0.6B-MLX-4bit")
}

@Test func qwenRepositoryDirectoryMatchesTheHubDownloadLayout() {
    let root = URL(fileURLWithPath: "/tmp/OpenLoop/Qwen", isDirectory: true)
    let resolved = QwenMeetingTranscriber.repositoryDirectory(
        modelID: "aufklarer/Qwen3-ASR-1.7B-MLX-8bit",
        below: root
    )

    #expect(resolved.path
        == "/tmp/OpenLoop/Qwen/models/aufklarer/Qwen3-ASR-1.7B-MLX-8bit")

    let hostile = QwenMeetingTranscriber.repositoryDirectory(
        modelID: "../../outside",
        below: root
    ).standardizedFileURL.path
    #expect(hostile.hasPrefix(root.standardizedFileURL.path + "/"))
}

@Test func qwenVocabularyContextIsBoundedDeduplicatedAndOptional() {
    #expect(QwenMeetingTranscriber.context(from: []) == nil)
    #expect(QwenMeetingTranscriber.context(from: [
        " SGLC ",
        "sglc",
        "Redis",
        "",
    ]) == "Vocabulary and names: SGLC, Redis")
    #expect(QwenMeetingTranscriber.context(from: ["one", "two", "three"], limit: 2)
        == "Vocabulary and names: one, two")
}

@Test func qwenWindowContextCarriesOnlyABoundedStableTranscriptTail() {
    let prior = (1...80).map { "word\($0)" }.joined(separator: " ")
    let value = QwenMeetingTranscriber.context(
        from: ["SGLC", "Dhruv"],
        priorTranscript: prior,
        priorWordLimit: 4
    )

    #expect(value == "Vocabulary and names: SGLC, Dhruv\nPrior transcript context — continue after this; do not repeat it: word77 word78 word79 word80")
    #expect(QwenMeetingTranscriber.context(
        from: [],
        priorTranscript: " previous stable words ",
        priorWordLimit: 3
    ) == "Prior transcript context — continue after this; do not repeat it: previous stable words")
}

@Test func qwenTokenBudgetTracksDurationWithinModelLimits() {
    #expect(QwenMeetingTranscriber.maximumTokens(for: 0) == 64)
    #expect(QwenMeetingTranscriber.maximumTokens(for: 10) == 180)
    #expect(QwenMeetingTranscriber.maximumTokens(for: 3_600) == 448)
}

@Test func qwenLanguageSummaryRecognizesHinglishWithoutAUserPrompt() {
    #expect(QwenMeetingTranscriber.spokenLanguageSummary(
        text: "Release time क्या हम कम कर सकते हैं?",
        requested: nil
    ) == "en + hi")
    #expect(QwenMeetingTranscriber.spokenLanguageSummary(
        text: "हम कम कर सकते हैं",
        requested: nil
    ) == "hi")
    #expect(QwenMeetingTranscriber.spokenLanguageSummary(
        text: "Can we reduce it?",
        requested: nil
    ) == "en")
}

@Test func qwenStreamingRecognitionReusesWarmModelAndAppliesVocabulary() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = StreamingQwenModel()
    let loaderCount = LockedCounter()
    let transcriber = QwenMeetingTranscriber(
        modelStorageURL: root,
        fallback: UnusedQwenFallback(),
        modelLoader: { _, _, _ in
            loaderCount.increment()
            return model
        }
    )

    let partial = try await transcriber.transcribe(
        samples: [Float](repeating: 0.1, count: 9_600),
        sampleRate: 16_000,
        context: ["SGLC", "Dhruv"],
        isFinal: false
    )
    let final = try await transcriber.transcribe(
        samples: [Float](repeating: 0.1, count: 16_000),
        sampleRate: 16_000,
        context: ["SGLC", "Dhruv"],
        isFinal: true
    )

    #expect(partial == "partial Hinglish")
    #expect(final == "final Hinglish")
    #expect(loaderCount.value == 1)
    #expect(model.contexts == [
        "Vocabulary and names: SGLC, Dhruv",
        "Vocabulary and names: SGLC, Dhruv",
    ])
    #expect(model.languages == [nil, nil])
}

private final class StreamingQwenModel: QwenSpeechRecognizing, @unchecked Sendable {
    private(set) var contexts: [String?] = []
    private(set) var languages: [String?] = []
    private var callCount = 0

    func transcribe(
        audio: [Float],
        sampleRate: Int,
        language: String?,
        maxTokens: Int,
        context: String?
    ) -> String {
        contexts.append(context)
        languages.append(language)
        defer { callCount += 1 }
        return callCount == 0 ? " partial Hinglish " : " final Hinglish "
    }
}

private actor UnusedQwenFallback: MeetingTranscribing {
    nonisolated let modelIdentifier = "unused"

    func transcribe(
        audioURL: URL,
        progress: @escaping @Sendable (MeetingTranscriptionProgress) async -> Void
    ) async throws -> LocalTranscriptionOutput {
        throw MeetingTranscriptionError.localModelUnavailable
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}
