import Foundation
import Testing
@testable import OpenLoopApp

@MainActor
@Test func permissionCallbackBridgeAcceptsAWorkerQueueCompletion() async {
    let granted = await PermissionCallbackBridge.resolve { completion in
        DispatchQueue.global(qos: .default).async {
            completion(true)
        }
    }

    #expect(granted)
}

@MainActor
@Test func audioTapCallbackBridgeAcceptsAWorkerQueueCompletion() async {
    let received = await withCheckedContinuation { continuation in
        let callback = AudioTapCallbackBridge.makeLevelCallback { value in
            continuation.resume(returning: value)
        }
        DispatchQueue.global(qos: .userInitiated).async {
            callback(0.42)
        }
    }

    #expect(received == 0.42)
}

@MainActor
private final class FakeVoiceTranscriber: VoiceTranscribing {
    var authorization: VoiceAuthorization = .authorized
    var startCount = 0
    var stopCount = 0
    var cancelCount = 0
    var configurations: [SpeechProviderConfiguration] = []
    private var update: (@MainActor @Sendable (String, Bool) -> Void)?
    private var audioLevel: (@MainActor @Sendable (Double) -> Void)?
    private var failure: (@MainActor @Sendable (String) -> Void)?

    func requestAuthorization() async -> VoiceAuthorization { authorization }

    func start(
        configuration: SpeechProviderConfiguration,
        onTranscript: @escaping @MainActor @Sendable (String, Bool) -> Void,
        onAudioLevel: @escaping @MainActor @Sendable (Double) -> Void,
        onFailure: @escaping @MainActor @Sendable (String) -> Void
    ) throws {
        startCount += 1
        configurations.append(configuration)
        update = onTranscript
        audioLevel = onAudioLevel
        failure = onFailure
    }

    func stop() { stopCount += 1 }
    func cancel() { cancelCount += 1 }
    func emit(_ text: String, final: Bool = false) { update?(text, final) }
    func emitLevel(_ value: Double) { audioLevel?(value) }
    func fail(_ message: String) { failure?(message) }
}

@MainActor
private final class VoiceSaveProbe {
    var allowed = false
    var attempts: [String] = []
}

@MainActor
private final class VoiceLearningProbe {
    var records: [(recognized: String, corrected: String, date: Date)] = []
}

@MainActor
@Test func oneToggleStartsAndSecondToggleStopsAndSavesNormalizedTranscript() async {
    let transcriber = FakeVoiceTranscriber()
    var saved: [String] = []
    let controller = VoiceTranscriptionController(transcriber: transcriber) { text in
        saved.append(text)
        return true
    }

    await controller.toggle()
    #expect(controller.state == .recording)
    #expect(transcriber.startCount == 1)

    transcriber.emit("  Draft the launch note  ")
    #expect(controller.transcript == "  Draft the launch note  ")
    await controller.toggle()

    #expect(transcriber.stopCount == 1)
    #expect(saved == ["Draft the launch note"])
    #expect(controller.state == .idle)
    #expect(controller.transcript.isEmpty)
}

@MainActor
@Test func partialResultsReplaceVisibleTextAndEmptyRecordingSavesNothing() async {
    let transcriber = FakeVoiceTranscriber()
    var saveCount = 0
    let controller = VoiceTranscriptionController(transcriber: transcriber) { _ in
        saveCount += 1
        return true
    }

    await controller.toggle()
    transcriber.emit("first partial")
    transcriber.emit("replacement partial")
    #expect(controller.transcript == "replacement partial")
    transcriber.emit("   ")
    await controller.toggle()

    #expect(saveCount == 0)
    #expect(controller.state == .idle)
}

@MainActor
@Test func denialAndRecognitionFailureReturnUsefulStateWithoutSaving() async {
    let deniedTranscriber = FakeVoiceTranscriber()
    deniedTranscriber.authorization = .denied(
        "Microphone access is off. Enable it in System Settings → Privacy & Security."
    )
    var saveCount = 0
    let denied = VoiceTranscriptionController(transcriber: deniedTranscriber) { _ in
        saveCount += 1
        return true
    }

    await denied.toggle()
    #expect(denied.state == .failed)
    #expect(denied.statusMessage.contains("System Settings"))
    #expect(deniedTranscriber.startCount == 0)

    let failingTranscriber = FakeVoiceTranscriber()
    let failing = VoiceTranscriptionController(transcriber: failingTranscriber) { _ in
        saveCount += 1
        return true
    }
    await failing.toggle()
    failingTranscriber.fail("On-device transcription stopped.")

    #expect(failing.state == .failed)
    #expect(failing.statusMessage == "On-device transcription stopped.")
    #expect(saveCount == 0)
}

@MainActor
@Test func failedSaveKeepsEditableTranscriptAndRetryUsesTheSameText() async {
    let transcriber = FakeVoiceTranscriber()
    let probe = VoiceSaveProbe()
    let controller = VoiceTranscriptionController(transcriber: transcriber) { text in
        probe.attempts.append(text)
        return probe.allowed
    }

    await controller.toggle()
    transcriber.emit("keep this transcript")
    await controller.toggle()
    #expect(controller.state == .failed)
    #expect(controller.transcript == "keep this transcript")

    probe.allowed = true
    await controller.toggle()
    #expect(probe.attempts == ["keep this transcript", "keep this transcript"])
    #expect(controller.state == .idle)
}

@MainActor
@Test func oneMinutePolicyAutomaticallyStopsAndSavesAtTheInjectedLimit() async throws {
    let transcriber = FakeVoiceTranscriber()
    var saved: [String] = []
    let controller = VoiceTranscriptionController(
        transcriber: transcriber,
        maximumDuration: .milliseconds(10)
    ) { text in
        saved.append(text)
        return true
    }
    await controller.toggle()
    transcriber.emit("automatic limit transcript")

    let deadline = ContinuousClock.now.advanced(by: .seconds(1))
    while controller.state != .idle && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(5))
    }

    #expect(controller.state == .idle)
    #expect(transcriber.stopCount == 1)
    #expect(saved == ["automatic limit transcript"])
}

@MainActor
@Test func cancelStopsAudioAndNeverSaves() async {
    let transcriber = FakeVoiceTranscriber()
    var saveCount = 0
    let controller = VoiceTranscriptionController(transcriber: transcriber) { _ in
        saveCount += 1
        return true
    }
    await controller.toggle()
    transcriber.emit("discard this")

    controller.cancel()

    #expect(transcriber.cancelCount == 1)
    #expect(saveCount == 0)
    #expect(controller.state == .idle)
    #expect(controller.transcript.isEmpty)
}

@MainActor
@Test func providerReceivesPrivateVocabularyAndActivityIsBoundedAndReset() async {
    let transcriber = FakeVoiceTranscriber()
    var vocabularyRequests = 0
    let controller = VoiceTranscriptionController(
        transcriber: transcriber,
        vocabulary: {
            vocabularyRequests += 1
            return ["Kuvam", "Open Xcode"]
        }
    ) { _ in true }

    await controller.toggle()

    #expect(vocabularyRequests == 1)
    #expect(transcriber.configurations == [SpeechProviderConfiguration(
        contextualPhrases: ["Kuvam", "Open Xcode"],
        requiresOnDeviceRecognition: true
    )])
    transcriber.emitLevel(2)
    #expect(controller.audioLevel == 1)
    #expect(controller.hasDetectedSpeech)
    transcriber.emitLevel(-1)
    #expect(controller.audioLevel == 0)
    #expect(controller.hasDetectedSpeech == false)
    controller.cancel()
    #expect(controller.audioLevel == 0)
}

@Test func audioLevelNormalizationAndVoiceActivityAreDeterministic() {
    #expect(AudioLevelNormalizer.normalized(rms: 0) == 0)
    #expect(AudioLevelNormalizer.normalized(rms: .nan) == 0)
    #expect(AudioLevelNormalizer.normalized(rms: 0.001) == 0)
    #expect(AudioLevelNormalizer.normalized(rms: 1) == 1)
    #expect(AudioLevelNormalizer.normalized(rms: 0.01) > 0.3)
    #expect(AudioLevelNormalizer.normalized(rms: 0.01) < 0.34)
    let detector = VoiceActivityDetector()
    #expect(detector.detects(level: 0.119) == false)
    #expect(detector.detects(level: 0.12))
}

@MainActor
@Test func editedTranscriptIsNotOverwrittenAndLearnsOnlyAfterSuccessfulSave() async {
    let transcriber = FakeVoiceTranscriber()
    let saveProbe = VoiceSaveProbe()
    let learningProbe = VoiceLearningProbe()
    let date = Date(timeIntervalSince1970: 42)
    let controller = VoiceTranscriptionController(
        transcriber: transcriber,
        now: { date },
        recordCorrection: { recognized, corrected, createdAt in
            learningProbe.records.append((recognized, corrected, createdAt))
        }
    ) { text in
        saveProbe.attempts.append(text)
        return saveProbe.allowed
    }

    await controller.toggle()
    transcriber.emit("Call cool van")
    controller.editTranscript("Call Kuvam")
    transcriber.emit("Call cool van tomorrow")
    #expect(controller.recognizedTranscript == "Call cool van tomorrow")
    #expect(controller.transcript == "Call Kuvam")

    await controller.toggle()
    #expect(controller.state == .failed)
    #expect(learningProbe.records.isEmpty)

    saveProbe.allowed = true
    await controller.toggle()
    #expect(saveProbe.attempts == ["Call Kuvam", "Call Kuvam"])
    #expect(learningProbe.records.count == 1)
    #expect(learningProbe.records[0].recognized == "Call cool van tomorrow")
    #expect(learningProbe.records[0].corrected == "Call Kuvam")
    #expect(learningProbe.records[0].date == date)
}

@MainActor
@Test func uneditedSuccessfulTranscriptDoesNotCreateCorrectionEvidence() async {
    let transcriber = FakeVoiceTranscriber()
    var correctionCount = 0
    let controller = VoiceTranscriptionController(
        transcriber: transcriber,
        recordCorrection: { _, _, _ in correctionCount += 1 }
    ) { _ in true }

    await controller.toggle()
    transcriber.emit("Exact transcript")
    await controller.toggle()

    #expect(correctionCount == 0)
}
