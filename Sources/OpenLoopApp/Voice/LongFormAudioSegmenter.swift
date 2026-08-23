import Foundation

struct SpeechAudioWindow: Equatable, Sendable {
    let startSample: Int
    let endSample: Int

    var sampleCount: Int { max(0, endSample - startSample) }
}

struct LongFormAudioSegmenter: Sendable {
    let frameDuration: TimeInterval
    let maximumWindowDuration: TimeInterval
    let maximumSilenceDuration: TimeInterval
    let paddingDuration: TimeInterval
    let boundarySearchDuration: TimeInterval

    init(
        frameDuration: TimeInterval = 0.030,
        maximumWindowDuration: TimeInterval = 18,
        maximumSilenceDuration: TimeInterval = 0.45,
        paddingDuration: TimeInterval = 0.20,
        boundarySearchDuration: TimeInterval = 1.5
    ) {
        self.frameDuration = frameDuration
        self.maximumWindowDuration = maximumWindowDuration
        self.maximumSilenceDuration = maximumSilenceDuration
        self.paddingDuration = paddingDuration
        self.boundarySearchDuration = max(0, boundarySearchDuration)
    }

    func windows(samples: [Float], sampleRate: Int) -> [SpeechAudioWindow] {
        guard !samples.isEmpty, sampleRate > 0 else { return [] }
        let maximumSamples = max(1, Int(maximumWindowDuration * Double(sampleRate)))
        if samples.count <= maximumSamples {
            return [SpeechAudioWindow(startSample: 0, endSample: samples.count)]
        }

        let frameSize = max(1, Int(frameDuration * Double(sampleRate)))
        let levels = stride(from: 0, to: samples.count, by: frameSize).map { start -> Float in
            let end = min(samples.count, start + frameSize)
            return Self.decibels(Array(samples[start..<end]))
        }
        let sorted = levels.sorted()
        let noiseIndex = min(sorted.count - 1, max(0, sorted.count / 5))
        let threshold = min(-24, max(-48, sorted[noiseIndex] + 9))
        let voiced = levels.enumerated().compactMap { index, level in
            level >= threshold ? index : nil
        }
        guard !voiced.isEmpty else {
            return Self.fixedWindows(sampleCount: samples.count, maximumSamples: maximumSamples)
        }

        let maximumSilentFrames = max(1, Int(maximumSilenceDuration / frameDuration))
        var frameRanges: [ClosedRange<Int>] = []
        var rangeStart = voiced[0]
        var previous = voiced[0]
        for index in voiced.dropFirst() {
            if index - previous > maximumSilentFrames {
                frameRanges.append(rangeStart...previous)
                rangeStart = index
            }
            previous = index
        }
        frameRanges.append(rangeStart...previous)

        let paddingSamples = max(0, Int(paddingDuration * Double(sampleRate)))
        return frameRanges.flatMap { range -> [SpeechAudioWindow] in
            let start = max(0, range.lowerBound * frameSize - paddingSamples)
            let end = min(samples.count, (range.upperBound + 1) * frameSize + paddingSamples)
            return Self.quietBoundaryWindows(
                samples: samples,
                startSample: start,
                endSample: end,
                maximumSamples: maximumSamples,
                sampleRate: sampleRate,
                searchDuration: boundarySearchDuration,
                frameDuration: frameDuration
            )
        }
    }

    private static func fixedWindows(
        sampleCount: Int,
        maximumSamples: Int
    ) -> [SpeechAudioWindow] {
        fixedWindows(startSample: 0, endSample: sampleCount, maximumSamples: maximumSamples)
    }

    private static func fixedWindows(
        startSample: Int,
        endSample: Int,
        maximumSamples: Int
    ) -> [SpeechAudioWindow] {
        var result: [SpeechAudioWindow] = []
        var start = startSample
        while start < endSample {
            let end = min(endSample, start + maximumSamples)
            result.append(SpeechAudioWindow(startSample: start, endSample: end))
            start = end
        }
        return result
    }

    private static func quietBoundaryWindows(
        samples: [Float],
        startSample: Int,
        endSample: Int,
        maximumSamples: Int,
        sampleRate: Int,
        searchDuration: TimeInterval,
        frameDuration: TimeInterval
    ) -> [SpeechAudioWindow] {
        var result: [SpeechAudioWindow] = []
        var start = startSample
        let searchSamples = max(0, Int(searchDuration * Double(sampleRate)))
        let frameSamples = max(1, Int(frameDuration * Double(sampleRate)))

        while endSample - start > maximumSamples {
            let ideal = start + maximumSamples
            let searchLower = max(start + maximumSamples / 2, ideal - searchSamples)
            let boundary = quietestBoundary(
                samples: samples,
                range: searchLower..<ideal,
                frameSamples: frameSamples
            )
            let safeBoundary = min(ideal, max(start + 1, boundary))
            result.append(SpeechAudioWindow(startSample: start, endSample: safeBoundary))
            start = safeBoundary
        }
        if start < endSample {
            result.append(SpeechAudioWindow(startSample: start, endSample: endSample))
        }
        return result
    }

    private static func quietestBoundary(
        samples: [Float],
        range: Range<Int>,
        frameSamples: Int
    ) -> Int {
        guard !range.isEmpty else { return range.lowerBound }
        var bestBoundary = range.upperBound
        var bestEnergy = Double.greatestFiniteMagnitude
        var candidate = range.lowerBound
        while candidate <= range.upperBound {
            let lower = max(0, candidate - frameSamples / 2)
            let upper = min(samples.count, candidate + frameSamples / 2)
            guard lower < upper else {
                candidate += frameSamples
                continue
            }
            let energy = samples[lower..<upper].reduce(0.0) {
                $0 + Double($1 * $1)
            } / Double(upper - lower)
            if energy < bestEnergy || (energy == bestEnergy && candidate > bestBoundary) {
                bestEnergy = energy
                bestBoundary = candidate
            }
            candidate += frameSamples
        }
        return bestBoundary
    }

    private static func decibels(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -60 }
        let meanSquare = samples.reduce(0.0) {
            $0 + Double($1 * $1)
        } / Double(samples.count)
        guard meanSquare.isFinite, meanSquare > 0 else { return -60 }
        return Float(min(0, max(-60, 20 * log10(sqrt(meanSquare)))))
    }
}
