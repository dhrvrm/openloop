import ADHDCore
import Foundation
import Testing
@testable import OpenLoopApp

@MainActor
@Test func importedAudioShowsProgressPersistsAndRemovesStagingCopy() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let audio = root.appendingPathComponent("meeting.m4a")
    try Data("audio fixture".utf8).write(to: audio)
    let repository = MeetingRepository()
    let transcriber = SuccessfulMeetingTranscriber()
    let controller = MeetingTranscriptionController(
        repository: repository,
        transcriber: transcriber,
        stagingDirectory: root.appendingPathComponent("staging")
    )
    controller.setLanguagePreference(.hindiHinglish)

    controller.importAudio(audio)
    await controller.waitUntilSettledForTesting()

    #expect(controller.job.stage == .ready)
    #expect(controller.job.message == "Transcript ready below and saved in Recall")
    #expect(controller.transcripts.count == 1)
    #expect(controller.transcripts[0].text == "नमस्ते team")
    #expect(controller.job.previewText == "नमस्ते team")
    #expect(controller.job.requestedLanguage == .hindiHinglish)
    #expect(await transcriber.latestLanguageCode() == "hi")
    #expect(controller.pipelineEvents.map(\.stage) == [
        .waitingForModel,
        .transcribing,
        .saving,
        .ready,
    ])
    #expect(try FileManager.default.contentsOfDirectory(
        at: root.appendingPathComponent("staging"),
        includingPropertiesForKeys: nil
    ).isEmpty)
}

@MainActor
@Test func liveRecordingStopsIntoTheSameLocalTranscriptionPipeline() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = FakeMeetingRecorder()
    let controller = MeetingTranscriptionController(
        repository: MeetingRepository(),
        transcriber: SuccessfulMeetingTranscriber(),
        stagingDirectory: root,
        recorder: recorder
    )

    await controller.toggleRecording()
    #expect(controller.job.stage == .recording)
    #expect(recorder.isRecording)

    await controller.toggleRecording()
    await controller.waitUntilSettledForTesting()
    #expect(controller.job.stage == .ready)
    #expect(controller.transcripts.first?.text == "नमस्ते team")
}

@MainActor
@Test func automaticLanguageDetectionPassesNoLanguageCodeToWhisper() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let audio = root.appendingPathComponent("multilingual.m4a")
    try Data("audio fixture".utf8).write(to: audio)
    let transcriber = SuccessfulMeetingTranscriber()
    let controller = MeetingTranscriptionController(
        repository: MeetingRepository(),
        transcriber: transcriber,
        stagingDirectory: root.appendingPathComponent("staging")
    )

    controller.importAudio(audio)
    await controller.waitUntilSettledForTesting()

    #expect(controller.job.stage == .ready)
    #expect(controller.job.requestedLanguage == .automatic)
    #expect(await transcriber.latestLanguageCode() == nil)
}

@MainActor
@Test func liveRecordingPublishesAndClearsDecibels() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = FakeMeetingRecorder()
    let controller = MeetingTranscriptionController(
        repository: MeetingRepository(),
        transcriber: SuccessfulMeetingTranscriber(),
        stagingDirectory: root,
        recorder: recorder
    )

    await controller.toggleRecording()
    recorder.emitDecibels(-23.5)

    #expect(controller.recordingDecibels == -23.5)

    await controller.toggleRecording()
    #expect(controller.recordingDecibels == nil)
    await controller.waitUntilSettledForTesting()
    #expect(controller.job.recordingPeakDecibels == -23.5)
    #expect((controller.job.recordingDuration ?? 0) >= 0)
}

@MainActor
@Test func failedRecordingExplainsCapturedSignal() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = FakeMeetingRecorder()
    let controller = MeetingTranscriptionController(
        repository: MeetingRepository(),
        transcriber: EmptyMeetingTranscriber(),
        stagingDirectory: root,
        recorder: recorder
    )

    await controller.toggleRecording()
    recorder.emitDecibels(-18)
    await controller.toggleRecording()
    await controller.waitUntilSettledForTesting()

    #expect(controller.job.stage == .failed)
    #expect(controller.job.message.contains("peak -18 dB"))
    #expect(controller.job.message.contains("Speech reached the microphone"))
    #expect(controller.job.previewText == nil)
}

@MainActor
@Test func interruptedFinalizationRetainsCaptureMeasurements() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = FakeMeetingRecorder()
    let controller = MeetingTranscriptionController(
        repository: MeetingRepository(),
        transcriber: SuccessfulMeetingTranscriber(),
        stagingDirectory: root,
        recorder: recorder
    )

    await controller.toggleRecording()
    recorder.emitDecibels(-14)
    recorder.shouldFailStop = true
    await controller.toggleRecording()

    #expect(controller.job.stage == .failed)
    #expect(controller.job.recordingPeakDecibels == -14)
    #expect(controller.job.recordingDuration != nil)
}

@MainActor
@Test func retryDoesNotRunAfterStagedAudioDisappears() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let audio = root.appendingPathComponent("meeting.m4a")
    try Data("audio fixture".utf8).write(to: audio)
    let transcriber = EmptyMeetingTranscriber()
    let controller = MeetingTranscriptionController(
        repository: MeetingRepository(),
        transcriber: transcriber,
        stagingDirectory: root.appendingPathComponent("staging")
    )

    controller.importAudio(audio)
    await controller.waitUntilSettledForTesting()
    let stagedURL = try #require(controller.job.stagedAudioURL)
    try FileManager.default.removeItem(at: stagedURL)
    controller.retry()

    #expect(controller.job.stage == .failed)
    #expect(await transcriber.transcriptionCount() == 1)
}

private actor SuccessfulMeetingTranscriber: MeetingTranscribing {
    nonisolated let modelIdentifier = "local-test-model"
    private var languageCodes: [String?] = []

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
        languageCodes.append(languageCode)
        await progress(.init(
            stage: .transcribing,
            fraction: 0.5,
            message: "Halfway",
            previewText: "नमस्ते"
        ))
        return LocalTranscriptionOutput(
            duration: 4,
            detectedLanguage: "hi",
            modelIdentifier: modelIdentifier,
            segments: [try TranscriptSegment(start: 0, end: 4, text: "नमस्ते team")]
        )
    }

    func latestLanguageCode() -> String? {
        languageCodes.last ?? nil
    }
}

private actor EmptyMeetingTranscriber: MeetingTranscribing {
    nonisolated let modelIdentifier = "local-test-model"
    private var count = 0

    func transcribe(
        audioURL: URL,
        progress: @escaping @Sendable (MeetingTranscriptionProgress) async -> Void
    ) async throws -> LocalTranscriptionOutput {
        count += 1
        await progress(.init(
            stage: .transcribing,
            fraction: 0.5,
            message: "Partial utterance",
            previewText: "discarded partial text"
        ))
        throw MeetingTranscriptionError.emptyTranscript
    }

    func transcriptionCount() -> Int { count }
}

private actor MeetingRepository: ThoughtRepository {
    private var values: [MeetingTranscript] = []

    func save(meetingTranscript: MeetingTranscript) async throws { values.append(meetingTranscript) }
    func meetingTranscripts() async throws -> [MeetingTranscript] { values }
    func deleteMeetingTranscript(id: UUID) async throws { values.removeAll { $0.id == id } }
    func save(capture: RawCapture) async throws {}
    func save(proposal: ClarificationProposal) async throws {}
    func save(intention: Intention) async throws {}
    func captures(disposition: Disposition) async throws -> [RawCapture] { [] }
    func intention(id: UUID) async throws -> Intention? { nil }
    func openIntentions() async throws -> [Intention] { [] }
    func proposal(captureID: UUID) async throws -> ClarificationProposal? { nil }
}

@MainActor
private final class FakeMeetingRecorder: MeetingAudioRecording {
    private(set) var isRecording = false
    private var url: URL?
    var onDecibelUpdate: ((Float?) -> Void)?
    var shouldFailStop = false

    func requestPermission() async -> Bool { true }
    func start(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("recording".utf8).write(to: url)
        self.url = url
        isRecording = true
    }
    func stop() -> URL? {
        isRecording = false
        if shouldFailStop { return nil }
        return url
    }
    func cancel() {
        isRecording = false
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    func emitDecibels(_ value: Float) {
        onDecibelUpdate?(value)
    }
}
