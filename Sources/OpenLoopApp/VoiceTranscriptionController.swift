@preconcurrency import AVFoundation
import Combine
import Foundation
@preconcurrency import Speech

enum VoiceAuthorization: Equatable {
    case authorized
    case denied(String)
}

struct SpeechProviderConfiguration: Equatable, Sendable {
    let contextualPhrases: [String]
    let requiresOnDeviceRecognition: Bool
}

enum AudioLevelNormalizer {
    static func normalized(rms: Double) -> Double {
        guard rms.isFinite, rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return min(1, max(0, (decibels + 60) / 60))
    }
}

struct VoiceActivityDetector: Sendable {
    let threshold: Double

    init(threshold: Double = 0.12) {
        self.threshold = threshold
    }

    func detects(level: Double) -> Bool {
        level >= threshold
    }
}

@MainActor
protocol VoiceTranscribing: AnyObject {
    func requestAuthorization() async -> VoiceAuthorization
    func start(
        configuration: SpeechProviderConfiguration,
        onTranscript: @escaping @MainActor @Sendable (String, Bool) -> Void,
        onAudioLevel: @escaping @MainActor @Sendable (Double) -> Void,
        onFailure: @escaping @MainActor @Sendable (String) -> Void
    ) throws
    func stop()
    func cancel()
}

enum VoiceCaptureState: Equatable {
    case idle
    case requestingPermission
    case recording
    case saving
    case failed
}

@MainActor
final class VoiceTranscriptionController: ObservableObject {
    @Published private(set) var state: VoiceCaptureState = .idle
    @Published var transcript = ""
    @Published private(set) var statusMessage = ""
    @Published private(set) var startedAt: Date?
    @Published private(set) var audioLevel = 0.0
    @Published private(set) var hasDetectedSpeech = false

    private let transcriber: any VoiceTranscribing
    private let save: @MainActor (String) async -> Bool
    private let maximumDuration: Duration
    private let vocabulary: @MainActor @Sendable () async -> [String]
    private let activityDetector = VoiceActivityDetector()
    private var durationTask: Task<Void, Never>?

    init(
        transcriber: any VoiceTranscribing,
        maximumDuration: Duration = .seconds(60),
        vocabulary: @escaping @MainActor @Sendable () async -> [String] = { [] },
        save: @escaping @MainActor (String) async -> Bool
    ) {
        self.transcriber = transcriber
        self.maximumDuration = maximumDuration
        self.vocabulary = vocabulary
        self.save = save
    }

    func toggle() async {
        switch state {
        case .idle:
            await start()
        case .requestingPermission, .saving:
            return
        case .recording:
            await stopAndSave()
        case .failed:
            if normalizedTranscript.isEmpty {
                await start()
            } else {
                await saveTranscript()
            }
        }
    }

    func cancel() {
        durationTask?.cancel()
        durationTask = nil
        transcriber.cancel()
        resetActivity()
        transcript = ""
        statusMessage = ""
        startedAt = nil
        state = .idle
    }

    private func start() async {
        transcript = ""
        statusMessage = "Checking microphone and speech access…"
        state = .requestingPermission
        switch await transcriber.requestAuthorization() {
        case .denied(let message):
            resetActivity()
            statusMessage = message
            state = .failed
        case .authorized:
            do {
                let phrases = Array((await vocabulary()).prefix(100))
                try transcriber.start(
                    configuration: SpeechProviderConfiguration(
                        contextualPhrases: phrases,
                        requiresOnDeviceRecognition: true
                    ),
                    onTranscript: { [weak self] text, isFinal in
                        guard let self else { return }
                        self.transcript = text
                        if isFinal {
                            Task { @MainActor [weak self] in
                                await self?.stopAndSave()
                            }
                        }
                    },
                    onAudioLevel: { [weak self] value in
                        guard let self else { return }
                        let bounded = min(1, max(0, value.isFinite ? value : 0))
                        self.audioLevel = bounded
                        self.hasDetectedSpeech = self.activityDetector.detects(level: bounded)
                    },
                    onFailure: { [weak self] message in
                        self?.handleFailure(message)
                    }
                )
                startedAt = .now
                statusMessage = "Recording · transcribing on device"
                state = .recording
                startDurationLimit()
            } catch {
                transcriber.cancel()
                resetActivity()
                statusMessage = "Recording could not start. Check the selected microphone."
                state = .failed
            }
        }
    }

    private func stopAndSave() async {
        guard state == .recording else { return }
        durationTask?.cancel()
        durationTask = nil
        transcriber.stop()
        resetActivity()
        startedAt = nil
        await saveTranscript()
    }

    private func saveTranscript() async {
        let value = normalizedTranscript
        guard value.isEmpty == false else {
            transcript = ""
            statusMessage = ""
            state = .idle
            return
        }
        statusMessage = "Saving transcript locally…"
        state = .saving
        if await save(value) {
            transcript = ""
            statusMessage = ""
            state = .idle
        } else {
            transcript = value
            statusMessage = "Transcript could not be saved. It is still editable here."
            state = .failed
        }
    }

    private func handleFailure(_ message: String) {
        durationTask?.cancel()
        durationTask = nil
        transcriber.cancel()
        resetActivity()
        startedAt = nil
        statusMessage = message
        state = .failed
    }

    private func startDurationLimit() {
        durationTask?.cancel()
        durationTask = Task { @MainActor [weak self, maximumDuration] in
            try? await Task.sleep(for: maximumDuration)
            guard Task.isCancelled == false else { return }
            await self?.stopAndSave()
        }
    }

    private func resetActivity() {
        audioLevel = 0
        hasDetectedSpeech = false
    }

    private var normalizedTranscript: String {
        transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class OnDeviceSpeechTranscriber: VoiceTranscribing {
    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var running = false
    private var failureHandler: (@MainActor (String) -> Void)?

    init(locale: Locale = .current) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    func requestAuthorization() async -> VoiceAuthorization {
        guard let recognizer, recognizer.supportsOnDeviceRecognition else {
            return .denied(
                "On-device transcription is unavailable for this language. "
                    + "Choose a supported Dictation language in System Settings."
            )
        }
        guard await requestSpeechAuthorization() else {
            return .denied(
                "Speech Recognition access is off. Enable OpenLoop in System Settings "
                    + "→ Privacy & Security → Speech Recognition."
            )
        }
        guard await requestMicrophoneAuthorization() else {
            return .denied(
                "Microphone access is off. Enable OpenLoop in System Settings "
                    + "→ Privacy & Security → Microphone."
            )
        }
        return .authorized
    }

    func start(
        configuration: SpeechProviderConfiguration,
        onTranscript: @escaping @MainActor @Sendable (String, Bool) -> Void,
        onAudioLevel: @escaping @MainActor @Sendable (Double) -> Void,
        onFailure: @escaping @MainActor @Sendable (String) -> Void
    ) throws {
        guard configuration.requiresOnDeviceRecognition,
              let recognizer, recognizer.supportsOnDeviceRecognition else {
            throw VoiceTranscriberError.onDeviceRecognitionUnavailable
        }
        teardown(cancelled: true)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = true
        request.contextualStrings = Array(configuration.contextualPhrases.prefix(100))
        recognitionRequest = request
        failureHandler = onFailure
        running = true
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.running else { return }
                if let result {
                    onTranscript(result.bestTranscription.formattedString, result.isFinal)
                }
                if error != nil {
                    onFailure("On-device transcription stopped. Press Command-Shift-R to try again.")
                }
            }
        }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak request] buffer, _ in
            let level: Double
            if let channel = buffer.floatChannelData?.pointee, buffer.frameLength > 0 {
                var sum = 0.0
                for index in 0..<Int(buffer.frameLength) {
                    let sample = Double(channel[index])
                    sum += sample * sample
                }
                level = AudioLevelNormalizer.normalized(
                    rms: sqrt(sum / Double(buffer.frameLength))
                )
            } else {
                level = 0
            }
            Task { @MainActor in onAudioLevel(level) }
            request?.append(buffer)
        }
        tapInstalled = true
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            teardown(cancelled: true)
            throw error
        }
    }

    func stop() {
        teardown(cancelled: false)
    }

    func cancel() {
        teardown(cancelled: true)
    }

    private func teardown(cancelled: Bool) {
        running = false
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        audioEngine.stop()
        if cancelled {
            recognitionTask?.cancel()
        } else {
            recognitionRequest?.endAudio()
            recognitionTask?.finish()
        }
        recognitionTask = nil
        recognitionRequest = nil
        failureHandler = nil
    }

    private func requestSpeechAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        @unknown default:
            return false
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }
}

private enum VoiceTranscriberError: Error {
    case onDeviceRecognitionUnavailable
}
