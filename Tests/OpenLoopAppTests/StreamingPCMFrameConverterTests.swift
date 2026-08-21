import Foundation
import Testing
@testable import OpenLoopApp

@Test func pcmConverterEmitsExactTwentyMillisecondFramesAcrossInputBoundaries() {
    let converter = StreamingPCMFrameConverter()
    let first = converter.process(
        [Float](repeating: 0.25, count: 100),
        sourceSampleRate: 16_000
    )
    let second = converter.process(
        [Float](repeating: 0.25, count: 221),
        sourceSampleRate: 16_000
    )

    #expect(first.isEmpty)
    #expect(second.count == 1)
    #expect(second[0].count == 320)
    #expect(second[0].allSatisfy { $0 == 0.25 })
}

@Test func pcmConverterResamplesFortyEightKilohertzToSixteenKilohertz() {
    let converter = StreamingPCMFrameConverter()
    let source = [Float](repeating: 0.5, count: 960)

    let frames = converter.process(source, sourceSampleRate: 48_000)

    #expect(frames.count == 1)
    #expect(frames[0].count == 320)
    #expect(frames[0].allSatisfy { abs($0 - 0.5) < 0.000_001 })
}

@Test func pcmConverterResetsWhenHardwareSampleRateChanges() {
    let converter = StreamingPCMFrameConverter()
    _ = converter.process([Float](repeating: 0.1, count: 200), sourceSampleRate: 16_000)

    let frames = converter.process(
        [Float](repeating: 0.7, count: 960),
        sourceSampleRate: 48_000
    )

    #expect(frames.count == 1)
    #expect(frames[0].allSatisfy { abs($0 - 0.7) < 0.000_001 })
}

@Test func pcmFrameMeterProducesBoundedDecibels() {
    #expect(StreamingPCMFrameConverter.decibels(for: []).map { _ in false } == nil)
    #expect(StreamingPCMFrameConverter.decibels(for: [0, 0]) == -60)
    #expect(StreamingPCMFrameConverter.decibels(for: [1, 1]) == 0)
    let quiet = StreamingPCMFrameConverter.decibels(for: [0.01, 0.01])
    #expect(quiet! > -41)
    #expect(quiet! < -39)
}
