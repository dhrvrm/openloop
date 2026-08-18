import Testing
@testable import OpenLoopApp

@Suite struct UtteranceAudioChunkerTests {
    private let sampleRate = 16_000

    @Test func separatesUtterancesAcrossLongSilence() {
        let audio = samples([
            (0.6, 0),
            (1.0, 0.3),
            (0.8, 0),
            (1.1, 0.3),
            (0.5, 0),
        ])

        let ranges = UtteranceAudioChunker.ranges(in: audio, sampleRate: sampleRate)

        #expect(ranges.count == 2)
        #expect(ranges[0].lowerBound == Int(0.45 * Double(sampleRate)))
        #expect(ranges[0].upperBound == Int(1.75 * Double(sampleRate)))
        #expect(ranges[1].lowerBound == Int(2.25 * Double(sampleRate)))
        #expect(ranges[1].upperBound == Int(3.65 * Double(sampleRate)))
    }

    @Test func keepsBriefPauseInsideOneUtterance() {
        let audio = samples([
            (0.2, 0),
            (0.8, 0.3),
            (0.3, 0),
            (0.8, 0.3),
            (0.2, 0),
        ])

        #expect(UtteranceAudioChunker.ranges(in: audio, sampleRate: sampleRate).count == 1)
    }

    @Test func silenceProducesNoUtterances() {
        let audio = [Float](repeating: 0, count: sampleRate * 2)

        #expect(UtteranceAudioChunker.ranges(in: audio, sampleRate: sampleRate).isEmpty)
    }

    private func samples(_ sections: [(seconds: Double, amplitude: Float)]) -> [Float] {
        sections.flatMap { section in
            [Float](
                repeating: section.amplitude,
                count: Int(section.seconds * Double(sampleRate))
            )
        }
    }
}
