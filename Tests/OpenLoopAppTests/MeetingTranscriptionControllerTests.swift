import ADHDCore
import Foundation
import Testing
@testable import OpenLoopApp

@MainActor
@Test func importedAudioShowsProgressPersistsAndRetainsRetryableSource() async throws {
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
    #expect(controller.job.message == "Transcript ready below. Source audio is kept locally for retranscription.")
    #expect(controller.transcripts.count == 1)
    #expect(controller.transcripts[0].text == "नमस्ते team")
    #expect(controller.transcripts[0].sourceName == "नमस्ते team")
    #expect(controller.job.previewText == "नमस्ते team")
    #expect(controller.job.requestedLanguage == .hindiHinglish)
    #expect(await transcriber.latestLanguageCode() == "hi")
    #expect(controller.pipelineEvents.map(\.stage) == [
        .waitingForModel,
        .transcribing,
        .saving,
        .ready,
    ])
    let retainedURL = try #require(controller.job.stagedAudioURL)
    #expect(FileManager.default.fileExists(atPath: retainedURL.path))
    #expect(controller.job.canRetry)
    #expect(controller.job.completedTranscriptID == controller.transcripts[0].id)
    #expect(controller.transcripts[0].sourceAudioFileName == retainedURL.lastPathComponent)
}

@MainActor
@Test func retranscribingRetainedSourceReplacesWrongTranscriptID() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let audio = root.appendingPathComponent("mixed.m4a")
    try Data("audio fixture".utf8).write(to: audio)
    let repository = MeetingRepository()
    let controller = MeetingTranscriptionController(
        repository: repository,
        transcriber: SequenceMeetingTranscriber(texts: ["wrong transcript", "अब सही transcript"]),
        stagingDirectory: root.appendingPathComponent("staging")
    )

    controller.importAudio(audio)
    await controller.waitUntilSettledForTesting()
    let originalID = try #require(controller.transcripts.first?.id)
    controller.retry()
    await controller.waitUntilSettledForTesting()

    #expect(controller.transcripts.count == 1)
    #expect(controller.transcripts.first?.id == originalID)
    #expect(controller.transcripts.first?.text == "अब सही transcript")
    #expect(controller.job.completedTranscriptID == originalID)
}

@MainActor
@Test func correctingMeetingSegmentAtomicallyPreservesRawLearningEvidence() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let audio = root.appendingPathComponent("meeting.m4a")
    try Data("audio fixture".utf8).write(to: audio)
    let repository = MeetingRepository()
    let controller = MeetingTranscriptionController(
        repository: repository,
        transcriber: SequenceMeetingTranscriber(texts: ["हम SGVC release काम करें"]),
        stagingDirectory: root.appendingPathComponent("staging")
    )
    controller.importAudio(audio)
    await controller.waitUntilSettledForTesting()
    let transcript = try #require(controller.transcripts.first)
    let segment = try #require(transcript.segments.first)

    let saved = await controller.correctSegment(
        transcriptID: transcript.id,
        segmentID: segment.id,
        correctedText: "हम SGLC release कम करें",
        scope: .project,
        projectIdentifier: "release-platform",
        at: Date(timeIntervalSince1970: 30)
    )

    #expect(saved)
    #expect(controller.transcripts.first?.text == "हम SGLC release कम करें")
    let corrections = await repository.storedCorrections()
    #expect(corrections.count == 1)
    #expect(corrections[0].recognized == "हम SGVC release काम करें")
    #expect(corrections[0].corrected == "हम SGLC release कम करें")
    #expect(corrections[0].scope == .project)
    #expect(corrections[0].projectIdentifier == "release-platform")
}

@MainActor
@Test func dismissingCompletedJobExplicitlyDiscardsRetainedAudio() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let audio = root.appendingPathComponent("meeting.m4a")
    try Data("audio fixture".utf8).write(to: audio)
    let controller = MeetingTranscriptionController(
        repository: MeetingRepository(),
        transcriber: SuccessfulMeetingTranscriber(),
        stagingDirectory: root.appendingPathComponent("staging")
    )

    controller.importAudio(audio)
    await controller.waitUntilSettledForTesting()
    let retainedURL = try #require(controller.job.stagedAudioURL)
    controller.clearFinishedJob()

    #expect(!FileManager.default.fileExists(atPath: retainedURL.path))
    #expect(controller.job.stage == nil)
}

@MainActor
@Test func refreshRestoresNewestRetainedSourceForRetranscription() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let staging = root.appendingPathComponent("staging", isDirectory: true)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    let sourceURL = staging.appendingPathComponent("retained.m4a")
    try Data("audio fixture".utf8).write(to: sourceURL)
    let repository = MeetingRepository()
    let transcript = try MeetingTranscript(
        sourceName: "meeting.m4a",
        duration: 4,
        modelIdentifier: "local-test-model",
        segments: [try TranscriptSegment(start: 0, end: 4, text: "saved transcript")],
        sourceAudioFileName: sourceURL.lastPathComponent
    )
    try await repository.save(meetingTranscript: transcript)
    let controller = MeetingTranscriptionController(
        repository: repository,
        transcriber: SuccessfulMeetingTranscriber(),
        stagingDirectory: staging
    )

    await controller.refresh()

    #expect(controller.job.stage == .ready)
    #expect(controller.job.canRetry)
    #expect(controller.job.completedTranscriptID == transcript.id)
    let renamedURL = try #require(controller.job.stagedAudioURL)
    #expect(renamedURL != sourceURL)
    #expect(renamedURL.lastPathComponent.hasSuffix("-saved-transcript.m4a"))
    #expect(FileManager.default.fileExists(atPath: renamedURL.path))
    #expect(!FileManager.default.fileExists(atPath: sourceURL.path))
    let refreshedTranscript = try #require(controller.transcripts.first)
    #expect(refreshedTranscript.sourceName == "saved transcript")
    #expect(refreshedTranscript.sourceAudioFileName == renamedURL.lastPathComponent)
    #expect(controller.job.previewText == "saved transcript")
}

@MainActor
@Test func deletingTranscriptAlsoDeletesItsRetainedSource() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let audio = root.appendingPathComponent("meeting.m4a")
    try Data("audio fixture".utf8).write(to: audio)
    let controller = MeetingTranscriptionController(
        repository: MeetingRepository(),
        transcriber: SuccessfulMeetingTranscriber(),
        stagingDirectory: root.appendingPathComponent("staging")
    )

    controller.importAudio(audio)
    await controller.waitUntilSettledForTesting()
    let transcriptID = try #require(controller.transcripts.first?.id)
    let retainedURL = try #require(controller.job.stagedAudioURL)
    await controller.deleteTranscript(id: transcriptID)

    #expect(controller.transcripts.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: retainedURL.path))
    #expect(controller.job.stage == nil)
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
@Test func dictationRecordingUsesDedicatedQualityTranscriber() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = FakeMeetingRecorder()
    let meeting = PurposeMeetingTranscriber(text: "meeting transcript")
    let dictation = PurposeMeetingTranscriber(text: "higher quality dictation")
    let controller = MeetingTranscriptionController(
        repository: MeetingRepository(),
        transcriber: meeting,
        dictationTranscriber: dictation,
        stagingDirectory: root,
        recorder: recorder
    )

    await controller.toggleRecording(purpose: .dictation)
    await controller.toggleRecording(purpose: .dictation)
    await controller.waitUntilSettledForTesting()

    #expect(await meeting.transcriptionCount() == 0)
    #expect(await dictation.transcriptionCount() == 1)
    #expect(controller.transcripts.first?.text == "higher quality dictation")
}

@MainActor
@Test func meetingRecordingAndImportKeepCanonicalMeetingTranscriber() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let recorder = FakeMeetingRecorder()
    let meeting = PurposeMeetingTranscriber(text: "speaker-timed meeting")
    let dictation = PurposeMeetingTranscriber(text: "dictation text")
    let controller = MeetingTranscriptionController(
        repository: MeetingRepository(),
        transcriber: meeting,
        dictationTranscriber: dictation,
        stagingDirectory: root.appendingPathComponent("staging"),
        recorder: recorder
    )

    await controller.toggleRecording(purpose: .meeting)
    await controller.toggleRecording(purpose: .meeting)
    await controller.waitUntilSettledForTesting()
    controller.clearFinishedJob()
    let imported = root.appendingPathComponent("imported.m4a")
    try Data("audio fixture".utf8).write(to: imported)
    controller.importAudio(imported)
    await controller.waitUntilSettledForTesting()

    #expect(await meeting.transcriptionCount() == 2)
    #expect(await dictation.transcriptionCount() == 0)
}

@MainActor
@Test func liveRecordingStartsBeforeStreamingModelsFinishPreparing() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = FakeMeetingRecorder()
    let builder = GatedControllerStreamingBuilder()
    let controller = MeetingTranscriptionController(
        repository: MeetingRepository(),
        transcriber: SuccessfulMeetingTranscriber(),
        stagingDirectory: root,
        recorder: recorder,
        streamingBuilder: builder
    )

    await controller.toggleRecording()

    #expect(recorder.isRecording)
    #expect(controller.job.stage == .recording)
    #expect(controller.job.stagedAudioURL != nil)
    await builder.waitUntilRequested()
    #expect(recorder.isRecording)

    await builder.open()
    while recorder.onPCMFrame == nil { await Task.yield() }
    await controller.toggleRecording()
    await controller.waitUntilSettledForTesting()
    #expect(controller.job.stage == .ready)
}

@MainActor
@Test func liveRecordingPublishesVADGuidedPartialAndStableTranscript() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let recorder = FakeMeetingRecorder()
    let recognizer = ControllerStreamingRecognizer()
    let builder = ControllerStreamingBuilder(recognizer: recognizer)
    let controller = MeetingTranscriptionController(
        repository: MeetingRepository(),
        transcriber: SuccessfulMeetingTranscriber(),
        stagingDirectory: root,
        recorder: recorder,
        streamingBuilder: builder
    )

    await controller.toggleRecording()
    recorder.emitPCMFrame(controllerStreamingFrame(0.2))
    recorder.emitPCMFrame(controllerStreamingFrame(0.3))
    await controller.toggleRecording()

    let snapshot = try #require(controller.streamingSnapshot)
    #expect(snapshot.processedFrameCount == 2)
    #expect(snapshot.finalizedUtteranceCount == 1)
    #expect(snapshot.transcript.stableText == "release time कम कर सकते हैं")
    #expect(snapshot.transcript.unstableText.isEmpty)
    #expect(snapshot.vadState == .silence)
    #expect(await recognizer.callKinds() == [false, true])
    await controller.waitUntilSettledForTesting()
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

@MainActor
@Test func retryWaitsForCancelledTranscriptionToUnwind() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let audio = root.appendingPathComponent("meeting.m4a")
    try Data("audio fixture".utf8).write(to: audio)
    let transcriber = CancellableMeetingTranscriber()
    let controller = MeetingTranscriptionController(
        repository: MeetingRepository(),
        transcriber: transcriber,
        stagingDirectory: root.appendingPathComponent("staging")
    )

    controller.importAudio(audio)
    while controller.job.stage != .transcribing { await Task.yield() }
    controller.cancel()
    controller.retry()

    #expect(await transcriber.transcriptionCount() == 1)
    await controller.waitUntilSettledForTesting()
    #expect(controller.job.stage == .cancelled)
}

@MainActor
@Test func retryKeepsReplacementIDWhenRefreshAfterSaveFails() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let audio = root.appendingPathComponent("meeting.m4a")
    try Data("audio fixture".utf8).write(to: audio)
    let repository = MeetingRepository(failFetchAfterSave: true)
    let controller = MeetingTranscriptionController(
        repository: repository,
        transcriber: SuccessfulMeetingTranscriber(),
        stagingDirectory: root.appendingPathComponent("staging")
    )

    controller.importAudio(audio)
    await controller.waitUntilSettledForTesting()
    let persistedID = try #require(controller.job.completedTranscriptID)
    controller.retry()
    await controller.waitUntilSettledForTesting()

    let stored = await repository.storedValues()
    #expect(stored.count == 1)
    #expect(stored.first?.id == persistedID)
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

private actor PurposeMeetingTranscriber: MeetingTranscribing {
    nonisolated let modelIdentifier: String
    private let text: String
    private var count = 0

    init(text: String) {
        self.text = text
        modelIdentifier = "purpose-\(text)"
    }

    func transcribe(
        audioURL: URL,
        progress: @escaping @Sendable (MeetingTranscriptionProgress) async -> Void
    ) async throws -> LocalTranscriptionOutput {
        count += 1
        return LocalTranscriptionOutput(
            duration: 2,
            detectedLanguage: "en",
            modelIdentifier: modelIdentifier,
            segments: [try TranscriptSegment(start: 0, end: 2, text: text)]
        )
    }

    func transcriptionCount() -> Int { count }
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

private actor CancellableMeetingTranscriber: MeetingTranscribing {
    nonisolated let modelIdentifier = "local-test-model"
    private var count = 0

    func transcribe(
        audioURL: URL,
        progress: @escaping @Sendable (MeetingTranscriptionProgress) async -> Void
    ) async throws -> LocalTranscriptionOutput {
        count += 1
        await progress(.init(stage: .transcribing, fraction: 0.5, message: "Working"))
        while true {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func transcriptionCount() -> Int { count }
}

private actor SequenceMeetingTranscriber: MeetingTranscribing {
    nonisolated let modelIdentifier = "local-test-model"
    private let texts: [String]
    private var index = 0

    init(texts: [String]) {
        self.texts = texts
    }

    func transcribe(
        audioURL: URL,
        progress: @escaping @Sendable (MeetingTranscriptionProgress) async -> Void
    ) async throws -> LocalTranscriptionOutput {
        let text = texts[min(index, texts.count - 1)]
        index += 1
        await progress(.init(stage: .transcribing, fraction: 0.5, previewText: text))
        return LocalTranscriptionOutput(
            duration: 4,
            detectedLanguage: "en + hi",
            modelIdentifier: modelIdentifier,
            segments: [try TranscriptSegment(start: 0, end: 4, text: text)]
        )
    }
}

private actor MeetingRepository: ThoughtRepository {
    private var values: [MeetingTranscript] = []
    private var corrections: [TranscriptionCorrection] = []
    private let failFetchAfterSave: Bool
    private var didSave = false

    init(failFetchAfterSave: Bool = false) {
        self.failFetchAfterSave = failFetchAfterSave
    }

    func save(meetingTranscript: MeetingTranscript) async throws {
        if let index = values.firstIndex(where: { $0.id == meetingTranscript.id }) {
            values[index] = meetingTranscript
        } else {
            values.append(meetingTranscript)
        }
        didSave = true
    }
    func meetingTranscripts() async throws -> [MeetingTranscript] {
        if failFetchAfterSave, didSave { throw MeetingRepositoryFailure() }
        return values
    }
    func storedValues() -> [MeetingTranscript] { values }
    func storedCorrections() -> [TranscriptionCorrection] { corrections }
    func save(transcriptionCorrection: TranscriptionCorrection) async throws {
        corrections.append(transcriptionCorrection)
    }
    func transcriptionCorrections() async throws -> [TranscriptionCorrection] { corrections }
    func save(
        meetingTranscript: MeetingTranscript,
        transcriptionCorrection: TranscriptionCorrection
    ) async throws {
        if let index = values.firstIndex(where: { $0.id == meetingTranscript.id }) {
            values[index] = meetingTranscript
        } else {
            values.append(meetingTranscript)
        }
        corrections.append(transcriptionCorrection)
    }
    func deleteMeetingTranscript(id: UUID) async throws { values.removeAll { $0.id == id } }
    func save(capture: RawCapture) async throws {}
    func save(proposal: ClarificationProposal) async throws {}
    func save(intention: Intention) async throws {}
    func captures(disposition: Disposition) async throws -> [RawCapture] { [] }
    func intention(id: UUID) async throws -> Intention? { nil }
    func openIntentions() async throws -> [Intention] { [] }
    func proposal(captureID: UUID) async throws -> ClarificationProposal? { nil }
}

private struct MeetingRepositoryFailure: Error {}

@MainActor
private final class FakeMeetingRecorder: MeetingAudioRecording {
    private(set) var isRecording = false
    private var url: URL?
    var onDecibelUpdate: ((Float?) -> Void)?
    var onPCMFrame: (@MainActor @Sendable (StreamingVoiceFrame) -> Void)?
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

    func emitPCMFrame(_ frame: StreamingVoiceFrame) {
        onPCMFrame?(frame)
    }
}

private final class ControllerStreamingVAD: @unchecked Sendable,
    StreamingVoiceActivityDetecting {
    private var index = 0

    func process(samples: [Float]) throws -> [StreamingVADEvent] {
        defer { index += 1 }
        return index == 0 ? [.speechStarted] : [.speechEnded]
    }

    func finish() throws -> [StreamingVADEvent] { [] }
    func reset() { index = 0 }
}

private actor ControllerStreamingRecognizer: StreamingSpeechRecognizing {
    nonisolated let modelIdentifier = "controller-streaming-test"
    private var calls: [Bool] = []

    func transcribe(
        samples: [Float],
        sampleRate: Int,
        context: [String],
        isFinal: Bool
    ) async throws -> String {
        calls.append(isFinal)
        return isFinal ? "release time कम कर सकते हैं" : "release time कम"
    }

    func callKinds() -> [Bool] { calls }
}

private struct ControllerStreamingBuilder: StreamingVoiceSessionBuilding {
    let recognizer: ControllerStreamingRecognizer

    func make(
        onUpdate: @escaping StreamingVoiceSession.UpdateHandler
    ) async throws -> StreamingVoiceSession {
        StreamingVoiceSession(
            vad: ControllerStreamingVAD(),
            recognizer: recognizer,
            configuration: StreamingVoiceConfiguration(partialResultInterval: 0.020),
            onUpdate: onUpdate
        )
    }
}

private actor GatedControllerStreamingBuilder: StreamingVoiceSessionBuilding {
    private var requested = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var openWaiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func make(
        onUpdate: @escaping StreamingVoiceSession.UpdateHandler
    ) async throws -> StreamingVoiceSession {
        requested = true
        let waiters = requestWaiters
        requestWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        if !isOpen {
            await withCheckedContinuation { continuation in
                openWaiters.append(continuation)
            }
        }
        return StreamingVoiceSession(
            vad: ControllerStreamingVAD(),
            recognizer: ControllerStreamingRecognizer(),
            onUpdate: onUpdate
        )
    }

    func waitUntilRequested() async {
        if requested { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let waiters = openWaiters
        openWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}

private func controllerStreamingFrame(_ value: Float) -> StreamingVoiceFrame {
    StreamingVoiceFrame(
        samples: [Float](repeating: value, count: 320),
        decibels: -20
    )
}
