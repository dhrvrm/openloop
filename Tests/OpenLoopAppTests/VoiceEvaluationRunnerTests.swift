import ADHDCore
import Foundation
import Testing
@testable import OpenLoopApp

@Test func voiceEvaluationDetectsOrderedHindiEnglishRuns() {
    #expect(VoiceEvaluationLanguageDetector.sequence(
        in: "Hello Dhruv, अब मैं हिंदी में बोल रहा हूं. Back to the release."
    ) == ["en", "hi", "en"])
    #expect(VoiceEvaluationLanguageDetector.sequence(in: "१२३ — …") == [])
}

@Test func voiceEvaluationExportsScorerCompatibleEvidence() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let audioURL = directory.appendingPathComponent("mixed.wav")
    try Data([0]).write(to: audioURL)

    let transcriber = VoiceEvaluationFixtureTranscriber(output:
        LocalTranscriptionOutput(
            duration: 2.4,
            detectedLanguage: "en + hi",
            modelIdentifier: "fixture",
            segments: [
                try TranscriptSegment(
                    start: 0,
                    end: 2.4,
                    text: "Ship it फिर release check",
                    speaker: nil
                )
            ]
        )
    )
    let runner = VoiceEvaluationRunner(transcriber: transcriber)
    let rows = await runner.evaluate(
        [VoiceEvaluationReference(id: "mixed-1", audio: "mixed.wav")],
        relativeTo: directory,
        languageCode: nil
    )

    #expect(rows.count == 1)
    #expect(rows[0].id == "mixed-1")
    #expect(rows[0].hypothesis == "Ship it फिर release check")
    #expect(rows[0].languages == ["en", "hi", "en"])
    #expect(rows[0].segments.map(\.speaker) == ["Speaker 1"])
    #expect(rows[0].coldStart)
    #expect(rows[0].error == nil)
}

@Test func voiceEvaluationKeepsFailuresAndMarksLaterCasesWarm() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data([0]).write(to: directory.appendingPathComponent("one.wav"))
    try Data([0]).write(to: directory.appendingPathComponent("two.wav"))

    let transcriber = VoiceEvaluationFixtureTranscriber(output: nil)
    let rows = await VoiceEvaluationRunner(transcriber: transcriber).evaluate(
        [
            VoiceEvaluationReference(id: "one", audio: "one.wav"),
            VoiceEvaluationReference(id: "two", audio: "two.wav"),
        ],
        relativeTo: directory,
        languageCode: nil
    )

    #expect(rows.map(\.coldStart) == [true, false])
    #expect(rows.allSatisfy { $0.hypothesis.isEmpty })
    #expect(rows.allSatisfy { $0.error?.contains("emptyTranscript") == true })
}

@Test func voiceEvaluationCommandUsesHeadlessDefaultsAndExplicitPaths() throws {
    let root = URL(fileURLWithPath: "/tmp/openloop-eval", isDirectory: true)
    let command = try VoiceEvaluationCommand(
        arguments: [
            "--voice-eval",
            "--manifest", "fixtures/release.jsonl",
            "--output", "results/candidate.jsonl",
            "--engine", "qwen",
            "--language", "auto",
            "--data-directory", "models",
        ],
        currentDirectory: root
    )

    #expect(command.manifestURL.path == "/tmp/openloop-eval/fixtures/release.jsonl")
    #expect(command.outputURL.path == "/tmp/openloop-eval/results/candidate.jsonl")
    #expect(command.dataDirectory.path == "/tmp/openloop-eval/models")
    #expect(command.engine == .qwen)
    #expect(command.languageCode == nil)
}

private actor VoiceEvaluationFixtureTranscriber: MeetingTranscribing {
    nonisolated let modelIdentifier = "fixture"
    private let output: LocalTranscriptionOutput?

    init(output: LocalTranscriptionOutput?) {
        self.output = output
    }

    func transcribe(
        audioURL: URL,
        progress: @escaping @Sendable (MeetingTranscriptionProgress) async -> Void
    ) async throws -> LocalTranscriptionOutput {
        guard let output else { throw MeetingTranscriptionError.emptyTranscript }
        return output
    }
}
