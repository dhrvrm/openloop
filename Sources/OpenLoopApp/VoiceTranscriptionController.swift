@preconcurrency import AVFoundation
import Combine
import Foundation
@preconcurrency import Speech

enum VoiceAuthorization: Equatable {
    case authorized
    case denied(String)
}

@MainActor
protocol VoiceTranscribing: AnyObject {
    func requestAuthorization() async -> VoiceAuthorization
    func start(
        onTranscript: @escaping @MainActor (String, Bool) -> Void,
        onFailure: @escaping @MainActor (String) -> Void
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

    private let transcriber: any VoiceTranscribing
    private let save: @MainActor (String) async -> Bool
    private let maximumDuration: Duration
    private var durationTask: Task<Void, Never>?

    init(
        transcriber: any VoiceTranscribing,
        maximumDuration: Duration = .seconds(60),
        save: @escaping @MainActor (String) async -> Bool
    ) {
        self.transcriber = transcriber
        self.maximumDuration = maximumDuration
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
            statusMessage = message
            state = .failed
        case .authorized:
            do {
                try transcriber.start(
                    onTranscript: { [weak self] text, isFinal in
                        guard let self else { return }
                        self.transcript = text
                        if isFinal {
                            Task { @MainActor [weak self] in
                                await self?.stopAndSave()
                            }
                        }
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
        onTranscript: @escaping @MainActor (String, Bool) -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) throws {
        guard let recognizer, recognizer.supportsOnDeviceRecognition else {
            throw VoiceTranscriberError.onDeviceRecognitionUnavailable
        }
        teardown(cancelled: true)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = true
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
