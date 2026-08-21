import Foundation
import Testing
@testable import OpenLoopApp

@Test func speechConditionerRemovesSteadyDCWithoutCreatingNonFiniteSamples() {
    let conditioner = SpeechAudioConditioner()
    let output = conditioner.process(
        [Float](repeating: 0.25, count: 16_000),
        sampleRate: 16_000
    )

    let settled = output.suffix(8_000)
    let settledMean = settled.reduce(0, +) / Float(settled.count)
    #expect(abs(settledMean) < 0.001)
    #expect(output.allSatisfy(\.isFinite))
    #expect(output.allSatisfy { abs($0) <= 0.98 })
}

@Test func speechConditionerRaisesQuietSpeechButLeavesSilenceQuiet() {
    let sampleRate = 16_000
    let quietSpeech = (0..<sampleRate).map { index in
        Float(sin(2 * Double.pi * 220 * Double(index) / Double(sampleRate))) * 0.01
    }
    let inputRMS = rootMeanSquare(quietSpeech)
    let conditioned = SpeechAudioConditioner().process(quietSpeech, sampleRate: sampleRate)

    #expect(rootMeanSquare(conditioned) > inputRMS * 1.8)
    #expect(conditioned.allSatisfy { abs($0) <= 0.98 })

    let silence = SpeechAudioConditioner().process(
        [Float](repeating: 0, count: sampleRate),
        sampleRate: sampleRate
    )
    #expect(silence.allSatisfy { $0 == 0 })
}

@Test func speechConditionerResetMakesRepeatedInferenceDeterministic() {
    let samples = (0..<1_600).map { index in
        Float(sin(2 * Double.pi * 330 * Double(index) / 16_000)) * 0.08
    }
    let conditioner = SpeechAudioConditioner()
    let first = conditioner.process(samples, sampleRate: 16_000)
    conditioner.reset()
    let second = conditioner.process(samples, sampleRate: 16_000)

    #expect(first == second)
}

private func rootMeanSquare(_ samples: [Float]) -> Float {
    guard !samples.isEmpty else { return 0 }
    let meanSquare = samples.reduce(0.0) { result, sample in
        result + Double(sample * sample)
    } / Double(samples.count)
    return Float(sqrt(meanSquare))
}
