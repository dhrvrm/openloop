import AVFoundation
import Foundation

@MainActor
protocol MeetingAudioRecording: AnyObject {
    var isRecording: Bool { get }
    var onDecibelUpdate: ((Float?) -> Void)? { get set }
    var onPCMFrame: (@MainActor @Sendable (StreamingVoiceFrame) -> Void)? { get set }
    func requestPermission() async -> Bool
    func start(at url: URL) throws
    func stop() -> URL?
    func cancel()
}

extension MeetingAudioRecording {
    var onPCMFrame: (@MainActor @Sendable (StreamingVoiceFrame) -> Void)? {
        get { nil }
        set {}
    }
}

final class StreamingPCMFrameConverter: @unchecked Sendable {
    private let outputSampleRate: Int
    private let frameLength: Int
    private let lock = NSLock()
    private var sourceSamples: [Float] = []
    private var outputSamples: [Float] = []
    private var sourcePosition = 0.0
    private var activeSourceSampleRate: Int?

    init(outputSampleRate: Int = 16_000, frameLength: Int = 320) {
        self.outputSampleRate = outputSampleRate
        self.frameLength = frameLength
    }

    func process(_ samples: [Float], sourceSampleRate: Int) -> [[Float]] {
        guard !samples.isEmpty, sourceSampleRate > 0, outputSampleRate > 0, frameLength > 0 else {
            return []
        }
        lock.lock()
        defer { lock.unlock() }
        if activeSourceSampleRate != sourceSampleRate {
            sourceSamples = []
            outputSamples = []
            sourcePosition = 0
            activeSourceSampleRate = sourceSampleRate
        }
        sourceSamples.append(contentsOf: samples)
        let step = Double(sourceSampleRate) / Double(outputSampleRate)
        while sourcePosition + 1 < Double(sourceSamples.count) {
            let lowerIndex = Int(sourcePosition)
            let fraction = Float(sourcePosition - Double(lowerIndex))
            let lower = sourceSamples[lowerIndex]
            let upper = sourceSamples[lowerIndex + 1]
            outputSamples.append(lower + ((upper - lower) * fraction))
            sourcePosition += step
        }
        let removable = min(Int(sourcePosition), max(0, sourceSamples.count - 1))
        if removable > 0 {
            sourceSamples.removeFirst(removable)
            sourcePosition -= Double(removable)
        }

        var frames: [[Float]] = []
        while outputSamples.count >= frameLength {
            frames.append(Array(outputSamples.prefix(frameLength)))
            outputSamples.removeFirst(frameLength)
        }
        return frames
    }

    func reset() {
        lock.lock()
        sourceSamples = []
        outputSamples = []
        sourcePosition = 0
        activeSourceSampleRate = nil
        lock.unlock()
    }

    static func decibels(for samples: [Float]) -> Float? {
        guard !samples.isEmpty else { return nil }
        let meanSquare = samples.reduce(0.0) { partial, sample in
            partial + (Double(sample) * Double(sample))
        } / Double(samples.count)
        guard meanSquare.isFinite, meanSquare > 0 else { return -60 }
        return Float(min(0, max(-60, 20 * log10(sqrt(meanSquare)))))
    }
}

enum MeetingPCMCallbackBridge {
    nonisolated static func make(
        converter: StreamingPCMFrameConverter,
        deliver: @escaping @MainActor @Sendable (StreamingVoiceFrame) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
            let channelCount = max(1, Int(buffer.format.channelCount))
            let sampleCount = Int(buffer.frameLength)
            var mono = [Float](repeating: 0, count: sampleCount)
            for channelIndex in 0..<channelCount {
                let channel = channels[channelIndex]
                for sampleIndex in 0..<sampleCount {
                    mono[sampleIndex] += channel[sampleIndex] / Float(channelCount)
                }
            }
            let sourceRate = Int(buffer.format.sampleRate.rounded())
            for samples in converter.process(mono, sourceSampleRate: sourceRate) {
                let frame = StreamingVoiceFrame(
                    samples: samples,
                    capturedAt: .now,
                    decibels: StreamingPCMFrameConverter.decibels(for: samples)
                )
                Task { @MainActor in deliver(frame) }
            }
        }
    }
}

@MainActor
final class MeetingAudioRecorder: NSObject, MeetingAudioRecording, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var outputURL: URL?
    private var meterTimer: Timer?
    private var pcmEngine: AVAudioEngine?
    private let pcmConverter = StreamingPCMFrameConverter()

    var onDecibelUpdate: ((Float?) -> Void)?
    var onPCMFrame: (@MainActor @Sendable (StreamingVoiceFrame) -> Void)?

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
        do {
            try startPCMStreamingIfNeeded()
        } catch {
            value.stop()
            recorder = nil
            outputURL = nil
            throw error
        }
        startMetering()
    }

    func stop() -> URL? {
        guard let recorder, recorder.isRecording else { return nil }
        stopMetering()
        stopPCMStreaming()
        recorder.stop()
        self.recorder = nil
        return outputURL
    }

    func cancel() {
        stopMetering()
        stopPCMStreaming()
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

    private func startPCMStreamingIfNeeded() throws {
        guard let onPCMFrame else { return }
        stopPCMStreaming()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw MeetingAudioRecorderError.invalidInputFormat
        }
        pcmConverter.reset()
        input.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format,
            block: MeetingPCMCallbackBridge.make(
                converter: pcmConverter,
                deliver: onPCMFrame
            )
        )
        do {
            engine.prepare()
            try engine.start()
            pcmEngine = engine
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    private func stopPCMStreaming() {
        guard let pcmEngine else {
            pcmConverter.reset()
            return
        }
        pcmEngine.inputNode.removeTap(onBus: 0)
        pcmEngine.stop()
        self.pcmEngine = nil
        pcmConverter.reset()
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
    case invalidInputFormat
}
