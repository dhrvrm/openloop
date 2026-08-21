import Foundation
import Testing
@testable import OpenLoopApp

@Test func longFormSegmenterBoundsAContinuousTwentyFiveMinuteMeeting() {
    let sampleRate = 100
    let samples = [Float](repeating: 0.2, count: sampleRate * 25 * 60)
    let segmenter = LongFormAudioSegmenter(
        frameDuration: 0.03,
        maximumWindowDuration: 18,
        maximumSilenceDuration: 0.45,
        paddingDuration: 0
    )

    let windows = segmenter.windows(samples: samples, sampleRate: sampleRate)

    #expect(windows.count > 80)
    #expect(windows.allSatisfy { $0.sampleCount <= sampleRate * 18 })
    #expect(windows.first?.startSample == 0)
    #expect(windows.last?.endSample == samples.count)
}

@Test func longFormSegmenterKeepsSeparatedSpeechAndDropsLongSilence() {
    let sampleRate = 1_000
    let speech = [Float](repeating: 0.2, count: sampleRate * 2)
    let silence = [Float](repeating: 0, count: sampleRate * 4)
    let samples = speech + silence + speech
    let segmenter = LongFormAudioSegmenter(
        frameDuration: 0.03,
        maximumWindowDuration: 3,
        maximumSilenceDuration: 0.3,
        paddingDuration: 0.1
    )

    let windows = segmenter.windows(samples: samples, sampleRate: sampleRate)

    #expect(windows.count == 2)
    #expect(windows[0].endSample < windows[1].startSample)
    #expect(windows.allSatisfy { $0.sampleCount <= sampleRate * 3 })
}
