import Foundation

struct LanguageProbe: Equatable, Sendable {
    let center: Int
    let language: String
    let confidenceMargin: Float
}

struct PlannedAudioChunk: Equatable, Sendable {
    let coreRange: Range<Int>
    let decodeRange: Range<Int>
}

enum CodeSwitchChunkPlanner {
    static func probeRanges(
        speechRanges: [Range<Int>],
        audioCount: Int,
        sampleRate: Int,
        probeDuration: TimeInterval = 2,
        probeStride: TimeInterval = 1,
        minimumSpeechDuration: TimeInterval = 4,
        maximumProbeCount: Int = 20
    ) -> [Range<Int>] {
        guard audioCount > 0, sampleRate > 0, maximumProbeCount > 0 else { return [] }
        let probeSamples = max(1, Int(probeDuration * Double(sampleRate)))
        let strideSamples = max(1, Int(probeStride * Double(sampleRate)))
        let minimumSamples = max(1, Int(minimumSpeechDuration * Double(sampleRate)))
        var output: [Range<Int>] = []

        for source in speechRanges {
            let range = max(0, source.lowerBound)..<min(audioCount, source.upperBound)
            guard range.count >= minimumSamples else { continue }
            var start = range.lowerBound
            while start < range.upperBound, output.count < maximumProbeCount {
                let upper = min(range.upperBound, start + probeSamples)
                let lower = max(range.lowerBound, upper - probeSamples)
                let candidate = lower..<upper
                if output.last != candidate { output.append(candidate) }
                if upper == range.upperBound { break }
                start += strideSamples
            }
            if output.count == maximumProbeCount { break }
        }
        return output
    }

    static func plan(
        audio: [Float],
        speechRanges: [Range<Int>],
        probes: [LanguageProbe],
        sampleRate: Int,
        minimumConfidenceMargin: Float = 0.35,
        context: TimeInterval = 1.25,
        maximumChunkCount: Int = 8
    ) -> [PlannedAudioChunk] {
        guard !audio.isEmpty, sampleRate > 0, maximumChunkCount > 0 else { return [] }
        var cores: [Range<Int>] = []

        for source in speechRanges {
            let range = max(0, source.lowerBound)..<min(audio.count, source.upperBound)
            guard !range.isEmpty else { continue }
            let stable = probes
                .filter { range.contains($0.center) && $0.confidenceMargin >= minimumConfidenceMargin }
                .sorted { $0.center < $1.center }
            let runs = languageRuns(stable)
            var cuts: [Int] = []
            for index in runs.indices.dropLast() {
                let left = runs[index]
                let right = runs[index + 1]
                guard left.language != right.language,
                      isStableRun(at: index, in: runs),
                      isStableRun(at: index + 1, in: runs),
                      let leftCenter = left.probes.last?.center,
                      let rightCenter = right.probes.first?.center
                else { continue }
                let midpoint = (leftCenter + rightCenter) / 2
                let cut = quietBoundary(
                    near: midpoint,
                    inside: range,
                    audio: audio,
                    sampleRate: sampleRate
                )
                if cut > range.lowerBound, cut < range.upperBound { cuts.append(cut) }
            }

            var lower = range.lowerBound
            for cut in cuts.sorted() where cut > lower {
                cores.append(lower..<cut)
                lower = cut
            }
            if lower < range.upperBound { cores.append(lower..<range.upperBound) }
        }

        guard !cores.isEmpty else { return [] }
        if cores.count > maximumChunkCount {
            let kept = Array(cores.prefix(maximumChunkCount - 1))
            let tail = cores[maximumChunkCount - 1].lowerBound..<(cores.last?.upperBound ?? audio.count)
            cores = kept + [tail]
        }

        let contextSamples = max(0, Int(context * Double(sampleRate)))
        return cores.map { core in
            PlannedAudioChunk(
                coreRange: core,
                decodeRange: max(0, core.lowerBound - contextSamples)..<min(
                    audio.count,
                    core.upperBound + contextSamples
                )
            )
        }
    }
}

private extension CodeSwitchChunkPlanner {
    struct LanguageRun {
        let language: String
        var probes: [LanguageProbe]

        var isOrdinarilyStable: Bool { probes.count >= 2 }
        var isExceptionalSingleton: Bool {
            probes.count == 1 && probes[0].confidenceMargin >= 0.95
        }
    }

    static func languageRuns(_ probes: [LanguageProbe]) -> [LanguageRun] {
        var runs: [LanguageRun] = []
        for probe in probes {
            let language = probe.language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !language.isEmpty else { continue }
            if runs.last?.language == language {
                runs[runs.count - 1].probes.append(probe)
            } else {
                runs.append(LanguageRun(language: language, probes: [probe]))
            }
        }
        return runs
    }

    static func isStableRun(at index: Int, in runs: [LanguageRun]) -> Bool {
        guard runs.indices.contains(index) else { return false }
        let run = runs[index]
        if run.isOrdinarilyStable { return true }
        guard run.isExceptionalSingleton,
              index > runs.startIndex,
              index < runs.index(before: runs.endIndex)
        else { return false }
        let left = runs[index - 1]
        let right = runs[index + 1]
        return left.isOrdinarilyStable
            && right.isOrdinarilyStable
            && left.language == right.language
    }

    static func quietBoundary(
        near midpoint: Int,
        inside range: Range<Int>,
        audio: [Float],
        sampleRate: Int
    ) -> Int {
        let radius = Int(1.5 * Double(sampleRate))
        let frame = max(1, Int(0.05 * Double(sampleRate)))
        let lower = max(range.lowerBound + 1, midpoint - radius)
        let upper = min(range.upperBound - 1, midpoint + radius)
        guard lower < upper else { return min(max(midpoint, range.lowerBound + 1), range.upperBound - 1) }

        var best = midpoint
        var bestEnergy = Float.greatestFiniteMagnitude
        var candidate = lower
        while candidate <= upper {
            let frameLower = max(range.lowerBound, candidate - frame / 2)
            let frameUpper = min(range.upperBound, candidate + frame / 2)
            let energy = audio[frameLower..<frameUpper].reduce(Float.zero) { partial, sample in
                partial + sample * sample
            } / Float(max(1, frameUpper - frameLower))
            if energy < bestEnergy {
                bestEnergy = energy
                best = candidate
            }
            candidate += frame
        }
        return best
    }
}
