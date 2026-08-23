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
    #expect(output.allSatisfy { $0.isFinite })
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

@Test func speechConditionerRecoversMuffledSpeechWithoutChangingTheSampleClock() {
    let sampleRate = 16_000
    let input = (0..<sampleRate).map { index -> Float in
        let time = Double(index) / Double(sampleRate)
        let muffledVoice = 0.025 * sin(2 * Double.pi * 260 * time)
            + 0.006 * sin(2 * Double.pi * 2_400 * time)
        let mainsHum = 0.018 * sin(2 * Double.pi * 50 * time)
        return Float(muffledVoice + mainsHum + 0.02)
    }

    let output = SpeechAudioConditioner().process(input, sampleRate: sampleRate)

    #expect(output.count == input.count)
    #expect(output.allSatisfy { $0.isFinite && abs($0) <= 0.98 })
    #expect(abs(output.suffix(sampleRate / 2).reduce(0, +) / Float(sampleRate / 2)) < 0.001)
    #expect(toneMagnitude(output, frequency: 2_400, sampleRate: sampleRate)
        > toneMagnitude(input, frequency: 2_400, sampleRate: sampleRate))
}

private func rootMeanSquare(_ samples: [Float]) -> Float {
    guard !samples.isEmpty else { return 0 }
    let meanSquare = samples.reduce(0.0) { result, sample in
        result + Double(sample * sample)
    } / Double(samples.count)
    return Float(sqrt(meanSquare))
}

private func toneMagnitude(_ samples: [Float], frequency: Double, sampleRate: Int) -> Double {
    guard !samples.isEmpty else { return 0 }
    var real = 0.0
    var imaginary = 0.0
    for (index, sample) in samples.enumerated() {
        let phase = 2 * Double.pi * frequency * Double(index) / Double(sampleRate)
        real += Double(sample) * cos(phase)
        imaginary -= Double(sample) * sin(phase)
    }
    return 2 * hypot(real, imaginary) / Double(samples.count)
}
