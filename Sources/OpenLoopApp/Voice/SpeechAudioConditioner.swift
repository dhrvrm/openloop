import Foundation

/// Conditions inference audio while leaving the durable source recording intact.
///
/// The state follows adjacent frames so live and batch inference use the same
/// high-pass and gain behavior. Silence is never promoted into apparent speech.
final class SpeechAudioConditioner: @unchecked Sendable {
    private let lock = NSLock()
    private let frameLength: Int
    private let highPassCutoff: Double
    private let targetRMSDecibels: Double
    private let silenceFloorDecibels: Double
    private let maximumGainDecibels: Double
    private let presenceBoost: Float

    private var activeSampleRate: Int?
    private var previousInput: Float = 0
    private var previousOutput: Float = 0
    private var previousPresenceInput: Float = 0
    private var smoothedGain: Float = 1

    init(
        frameLength: Int = 320,
        highPassCutoff: Double = 80,
        targetRMSDecibels: Double = -20,
        silenceFloorDecibels: Double = -52,
        maximumGainDecibels: Double = 12,
        presenceBoost: Float = 0.18
    ) {
        self.frameLength = max(1, frameLength)
        self.highPassCutoff = max(1, highPassCutoff)
        self.targetRMSDecibels = min(-6, targetRMSDecibels)
        self.silenceFloorDecibels = min(-30, silenceFloorDecibels)
        self.maximumGainDecibels = max(0, maximumGainDecibels)
        self.presenceBoost = min(0.35, max(0, presenceBoost))
    }

    func process(_ samples: [Float], sampleRate: Int) -> [Float] {
        guard !samples.isEmpty, sampleRate > 0 else { return [] }
        lock.lock()
        defer { lock.unlock() }

        if activeSampleRate != sampleRate {
            resetState(sampleRate: sampleRate)
        }

        var result: [Float] = []
        result.reserveCapacity(samples.count)
        var start = 0
        while start < samples.count {
            let end = min(samples.count, start + frameLength)
            result.append(contentsOf: processFrame(samples[start..<end], sampleRate: sampleRate))
            start = end
        }
        return result
    }

    func reset() {
        lock.lock()
        resetState(sampleRate: nil)
        lock.unlock()
    }

    private func processFrame(
        _ samples: ArraySlice<Float>,
        sampleRate: Int
    ) -> [Float] {
        let timeStep = 1 / Double(sampleRate)
        let resistanceCapacitance = 1 / (2 * Double.pi * highPassCutoff)
        let alpha = Float(resistanceCapacitance / (resistanceCapacitance + timeStep))
        var filtered: [Float] = []
        filtered.reserveCapacity(samples.count)
        for sample in samples {
            let cleanSample = sample.isFinite ? sample : 0
            let value = alpha * (previousOutput + cleanSample - previousInput)
            previousInput = cleanSample
            previousOutput = value
            let presence = value - previousPresenceInput
            previousPresenceInput = value
            filtered.append(value + presenceBoost * presence)
        }

        let meanSquare = filtered.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        } / Double(max(1, filtered.count))
        let rmsDecibels = meanSquare > 0
            ? 20 * log10(sqrt(meanSquare))
            : -Double.infinity
        let desiredGain: Float
        if rmsDecibels < silenceFloorDecibels {
            desiredGain = 1
        } else {
            let neededDecibels = min(maximumGainDecibels, targetRMSDecibels - rmsDecibels)
            desiredGain = Float(pow(10, neededDecibels / 20))
        }
        let response: Float = desiredGain > smoothedGain ? 0.28 : 0.08
        smoothedGain += (desiredGain - smoothedGain) * response

        return filtered.map { sample in
            min(0.98, max(-0.98, sample * smoothedGain))
        }
    }

    private func resetState(sampleRate: Int?) {
        activeSampleRate = sampleRate
        previousInput = 0
        previousOutput = 0
        previousPresenceInput = 0
        smoothedGain = 1
    }
}
