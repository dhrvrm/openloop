@preconcurrency import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

@MainActor
final class SystemAudioRecorder: MeetingAudioRecording {
    private var stream: SCStream?
    private var sink: SystemAudioCaptureSink?
    private var outputURL: URL?
    private var source: AudioCaptureSource?

    var onDecibelUpdate: ((Float?) -> Void)?
    var onPCMFrame: (@MainActor @Sendable (StreamingVoiceFrame) -> Void)?
    var isRecording: Bool { stream != nil }

    func requestPermission(for source: AudioCaptureSource) async -> Bool {
        if source.includesMicrophone {
            let microphoneGranted: Bool
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                microphoneGranted = true
            case .denied, .restricted:
                microphoneGranted = false
            case .notDetermined:
                microphoneGranted = await PermissionCallbackBridge.resolve { completion in
                    AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
                }
            @unknown default:
                microphoneGranted = false
            }
            guard microphoneGranted else { return false }
        }
        guard source.includesSystemAudio else { return true }
        return CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
    }

    func start(at url: URL, source: AudioCaptureSource) async throws {
        guard source.includesSystemAudio else {
            throw SystemAudioRecorderError.unsupportedSource
        }
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw SystemAudioRecorderError.noDisplay
        }

        let ownApplication = content.applications.first {
            $0.processID == ProcessInfo.processInfo.processIdentifier
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: ownApplication.map { [$0] } ?? [],
            exceptingWindows: []
        )
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 1
        configuration.excludesCurrentProcessAudio = true
        configuration.captureMicrophone = source.includesMicrophone

        let writerURL = source == .microphoneAndMac
            ? url.deletingPathExtension().appendingPathExtension("tracks.m4a")
            : url
        try? FileManager.default.removeItem(at: writerURL)
        try? FileManager.default.removeItem(at: url)

        let sink = try SystemAudioCaptureSink(
            outputURL: writerURL,
            includeMicrophone: source.includesMicrophone,
            previewOutput: source == .microphoneAndMac ? .microphone : .audio,
            onDecibels: { [weak self] value in
                Task { @MainActor in self?.onDecibelUpdate?(value) }
            },
            onFrame: { [weak self] frame in
                Task { @MainActor in self?.onPCMFrame?(frame) }
            }
        )
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: sink.captureQueue)
        if source.includesMicrophone {
            try stream.addStreamOutput(sink, type: .microphone, sampleHandlerQueue: sink.captureQueue)
        }
        do {
            try await stream.startCapture()
        } catch {
            sink.cancel()
            throw error
        }
        self.outputURL = url
        self.source = source
        self.sink = sink
        self.stream = stream
    }

    func stop() async -> URL? {
        guard let stream, let sink, let outputURL, let source else { return nil }
        do {
            try await stream.stopCapture()
        } catch {
            // The writer can still contain a complete local recording.
        }
        self.stream = nil
        self.sink = nil
        self.outputURL = nil
        self.source = nil
        onDecibelUpdate?(nil)

        guard let trackURL = await sink.finish() else { return nil }
        guard source == .microphoneAndMac else { return trackURL }
        do {
            try await Self.mixAudioTracks(from: trackURL, to: outputURL)
            try? FileManager.default.removeItem(at: trackURL)
            return outputURL
        } catch {
            return trackURL
        }
    }

    func cancel() {
        let stream = self.stream
        let sink = self.sink
        self.stream = nil
        self.sink = nil
        if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
        outputURL = nil
        source = nil
        onDecibelUpdate?(nil)
        sink?.cancel()
        Task { try? await stream?.stopCapture() }
    }

    private static func mixAudioTracks(from sourceURL: URL, to outputURL: URL) async throws {
        let asset = AVURLAsset(url: sourceURL)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw SystemAudioRecorderError.noAudio }
        let composition = AVMutableComposition()
        let duration = try await asset.load(.duration)
        var parameters: [AVMutableAudioMixInputParameters] = []
        for track in tracks {
            guard let destination = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }
            try destination.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: track,
                at: .zero
            )
            let input = AVMutableAudioMixInputParameters(track: destination)
            input.setVolume(tracks.count > 1 ? 0.72 : 1, at: .zero)
            parameters.append(input)
        }
        guard !parameters.isEmpty,
              let exporter = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetAppleM4A
              ) else { throw SystemAudioRecorderError.couldNotMix }
        let mix = AVMutableAudioMix()
        mix.inputParameters = parameters
        exporter.audioMix = mix
        try? FileManager.default.removeItem(at: outputURL)
        try await exporter.export(to: outputURL, as: .m4a)
    }
}

private final class SystemAudioCaptureSink: NSObject, SCStreamOutput, @unchecked Sendable {
    let captureQueue = DispatchQueue(label: "dev.openloop.system-audio", qos: .userInitiated)

    private let writer: AVAssetWriter
    private let systemInput: AVAssetWriterInput
    private let microphoneInput: AVAssetWriterInput?
    private let previewOutput: SCStreamOutputType
    private let onDecibels: @Sendable (Float?) -> Void
    private let onFrame: @Sendable (StreamingVoiceFrame) -> Void
    private let converter = StreamingPCMFrameConverter()
    private let conditioner = SpeechAudioConditioner()
    private var started = false
    private var cancelled = false

    init(
        outputURL: URL,
        includeMicrophone: Bool,
        previewOutput: SCStreamOutputType,
        onDecibels: @escaping @Sendable (Float?) -> Void,
        onFrame: @escaping @Sendable (StreamingVoiceFrame) -> Void
    ) throws {
        writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 160_000,
        ]
        systemInput = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        microphoneInput = includeMicrophone
            ? AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            : nil
        self.previewOutput = previewOutput
        self.onDecibels = onDecibels
        self.onFrame = onFrame
        super.init()
        systemInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(systemInput) else { throw SystemAudioRecorderError.couldNotStart }
        writer.add(systemInput)
        if let microphoneInput {
            microphoneInput.expectsMediaDataInRealTime = true
            guard writer.canAdd(microphoneInput) else {
                throw SystemAudioRecorderError.couldNotStart
            }
            writer.add(microphoneInput)
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard !cancelled,
              sampleBuffer.isValid,
              CMSampleBufferDataIsReady(sampleBuffer),
              type == .audio || type == .microphone
        else { return }
        if !started {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
            started = true
        }
        let input = type == .microphone ? microphoneInput : systemInput
        if input?.isReadyForMoreMediaData == true {
            _ = input?.append(sampleBuffer)
        }
        if type == previewOutput {
            publishPreview(from: sampleBuffer)
        }
    }

    func finish() async -> URL? {
        await withCheckedContinuation { continuation in
            captureQueue.async { [self] in
                guard !cancelled, started else {
                    continuation.resume(returning: nil)
                    return
                }
                systemInput.markAsFinished()
                microphoneInput?.markAsFinished()
                writer.finishWriting { [self] in
                    continuation.resume(
                        returning: writer.status == .completed ? writer.outputURL : nil
                    )
                }
            }
        }
    }

    func cancel() {
        captureQueue.async { [self] in
            cancelled = true
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: writer.outputURL)
        }
    }

    private func publishPreview(from sampleBuffer: CMSampleBuffer) {
        guard let format = sampleBuffer.formatDescription,
              let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              description.mFormatID == kAudioFormatLinearPCM,
              description.mBitsPerChannel > 0
        else { return }
        let channels = max(1, Int(description.mChannelsPerFrame))
        let nonInterleaved = description.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let isFloat = description.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let isSignedInteger = description.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0
        let bytesPerSample = Int(description.mBitsPerChannel) / 8
        guard (isFloat && bytesPerSample == 4)
                || (isSignedInteger && (bytesPerSample == 2 || bytesPerSample == 4))
        else { return }
        let mono: [Float]
        do {
            mono = try sampleBuffer.withAudioBufferList { buffers, _ in
                func sample(_ data: UnsafeMutableRawPointer, at index: Int) -> Float {
                    if isFloat {
                        return data.assumingMemoryBound(to: Float.self)[index]
                    }
                    if bytesPerSample == 2 {
                        return Float(data.assumingMemoryBound(to: Int16.self)[index])
                            / Float(Int16.max)
                    }
                    return Float(data.assumingMemoryBound(to: Int32.self)[index])
                        / Float(Int32.max)
                }
                if nonInterleaved {
                    let sampleCount = buffers.compactMap { buffer -> Int? in
                        guard buffer.mData != nil else { return nil }
                        return Int(buffer.mDataByteSize) / bytesPerSample
                    }.min() ?? 0
                    guard sampleCount > 0 else { return [] }
                    var result = [Float](repeating: 0, count: sampleCount)
                    for buffer in buffers {
                        guard let data = buffer.mData else { continue }
                        for index in 0..<sampleCount {
                            result[index] += sample(data, at: index) / Float(max(1, buffers.count))
                        }
                    }
                    return result
                }
                guard let buffer = buffers.first, let data = buffer.mData else { return [] }
                let valueCount = Int(buffer.mDataByteSize) / bytesPerSample
                let frameCount = valueCount / channels
                return (0..<frameCount).map { frame in
                    let start = frame * channels
                    return (0..<channels).reduce(Float.zero) {
                        $0 + sample(data, at: start + $1) / Float(channels)
                    }
                }
            }
        } catch {
            return
        }
        let sampleRate = Int(description.mSampleRate.rounded())
        for rawSamples in converter.process(mono, sourceSampleRate: sampleRate) {
            let samples = conditioner.process(rawSamples, sampleRate: 16_000)
            let decibels = StreamingPCMFrameConverter.decibels(for: rawSamples)
            onDecibels(decibels)
            onFrame(StreamingVoiceFrame(
                samples: samples,
                capturedAt: .now,
                decibels: decibels
            ))
        }
    }
}

enum SystemAudioRecorderError: Error {
    case unsupportedSource
    case noDisplay
    case noAudio
    case couldNotStart
    case couldNotMix
}
