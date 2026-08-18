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

    controller.importAudio(audio)
    await controller.waitUntilSettledForTesting()

    #expect(controller.job.stage == .ready)
    #expect(controller.job.message == "Transcript ready in Recall")
    #expect(controller.transcripts.count == 1)
    #expect(controller.transcripts[0].text == "नमस्ते team")
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

private actor SuccessfulMeetingTranscriber: MeetingTranscribing {
    nonisolated let modelIdentifier = "local-test-model"

    func transcribe(
        audioURL: URL,
        progress: @escaping @Sendable (MeetingTranscriptionProgress) async -> Void
    ) async throws -> LocalTranscriptionOutput {
        await progress(.init(stage: .transcribing, fraction: 0.5, message: "Halfway"))
        return LocalTranscriptionOutput(
            duration: 4,
            detectedLanguage: "hi",
            modelIdentifier: modelIdentifier,
            segments: [try TranscriptSegment(start: 0, end: 4, text: "नमस्ते team")]
        )
    }
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
        return url
    }
    func cancel() {
        isRecording = false
        if let url { try? FileManager.default.removeItem(at: url) }
    }
}
