import AVFoundation
import Foundation

@MainActor
protocol MeetingAudioRecording: AnyObject {
    var isRecording: Bool { get }
    var onDecibelUpdate: ((Float?) -> Void)? { get set }
    func requestPermission() async -> Bool
    func start(at url: URL) throws
    func stop() -> URL?
    func cancel()
}

@MainActor
final class MeetingAudioRecorder: NSObject, MeetingAudioRecording, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var outputURL: URL?
    private var meterTimer: Timer?

    var onDecibelUpdate: ((Float?) -> Void)?

    var isRecording: Bool { recorder?.isRecording == true }

    isolated deinit {
        meterTimer?.invalidate()
    }

    func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await PermissionCallbackBridge.resolve { completion in
                AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
            }
        @unknown default:
            return false
        }
    }

    func start(at url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 128_000,
        ]
        let value = try AVAudioRecorder(url: url, settings: settings)
        value.delegate = self
        value.isMeteringEnabled = true
        guard value.prepareToRecord(), value.record() else {
            throw MeetingAudioRecorderError.couldNotStart
        }
        outputURL = url
        recorder = value
        startMetering()
    }

    func stop() -> URL? {
        guard let recorder, recorder.isRecording else { return nil }
        stopMetering()
        recorder.stop()
        self.recorder = nil
        return outputURL
    }

    func cancel() {
        stopMetering()
        recorder?.stop()
        recorder = nil
        if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
        outputURL = nil
    }

    private func startMetering() {
        stopMetering()
        let timer = Timer(timeInterval: 0.06, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.publishMeterLevel()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
        onDecibelUpdate?(nil)
    }

    private func publishMeterLevel() {
        guard let recorder, recorder.isRecording else {
            stopMetering()
            return
        }
        recorder.updateMeters()
        let decibels = min(0, max(-60, recorder.averagePower(forChannel: 0)))
        onDecibelUpdate?(decibels)
    }
}

enum MeetingAudioRecorderError: Error {
    case couldNotStart
}
