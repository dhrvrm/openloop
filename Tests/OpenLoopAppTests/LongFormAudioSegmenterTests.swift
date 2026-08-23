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

@Test func longFormSegmenterMovesContinuousSpeechCutToTheQuietestNearbyBoundary() throws {
    let sampleRate = 1_000
    var samples = [Float](repeating: 0.2, count: sampleRate * 12)
    let quietStart = 7_850
    let quietEnd = 7_950
    for index in quietStart..<quietEnd { samples[index] = 0.002 }
    let segmenter = LongFormAudioSegmenter(
        frameDuration: 0.03,
        maximumWindowDuration: 8,
        maximumSilenceDuration: 0.45,
        paddingDuration: 0,
        boundarySearchDuration: 1.0
    )

    let windows = segmenter.windows(samples: samples, sampleRate: sampleRate)

    let first = try #require(windows.first)
    #expect((quietStart - 30)...(quietEnd + 30) ~= first.endSample)
    #expect(windows.allSatisfy { $0.sampleCount <= sampleRate * 8 })
    #expect(windows.first?.startSample == 0)
    #expect(windows.last?.endSample == samples.count)
    for pair in zip(windows, windows.dropFirst()) {
        #expect(pair.0.endSample == pair.1.startSample)
    }
}
