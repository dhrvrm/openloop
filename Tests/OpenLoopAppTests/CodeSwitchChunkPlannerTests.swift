import Testing
@testable import OpenLoopApp

@Suite struct CodeSwitchChunkPlannerTests {
    private let sampleRate = 100

    @Test func stableLanguageChangeSplitsContinuousSpeech() {
        let audio = [Float](repeating: 0.25, count: 1_600)
        let probes = [
            LanguageProbe(center: 200, language: "en", confidenceMargin: 0.8),
            LanguageProbe(center: 500, language: "en", confidenceMargin: 0.7),
            LanguageProbe(center: 900, language: "hi", confidenceMargin: 0.9),
            LanguageProbe(center: 1_200, language: "hi", confidenceMargin: 0.8),
        ]

        let chunks = CodeSwitchChunkPlanner.plan(
            audio: audio,
            speechRanges: [0..<1_600],
            probes: probes,
            sampleRate: sampleRate
        )

        #expect(chunks.count == 2)
        #expect(chunks[0].coreRange.lowerBound == 0)
        #expect(chunks[0].coreRange.upperBound == chunks[1].coreRange.lowerBound)
        #expect(chunks[1].coreRange.upperBound == 1_600)
        #expect(chunks[0].decodeRange.upperBound - chunks[0].coreRange.upperBound <= 125)
        #expect(chunks[1].coreRange.lowerBound - chunks[1].decodeRange.lowerBound <= 125)
    }

    @Test func noisyOrLowConfidenceProbeDoesNotSplit() {
        let audio = [Float](repeating: 0.2, count: 1_400)
        let noisy = [
            LanguageProbe(center: 200, language: "en", confidenceMargin: 0.8),
            LanguageProbe(center: 500, language: "en", confidenceMargin: 0.8),
            LanguageProbe(center: 800, language: "hi", confidenceMargin: 0.9),
            LanguageProbe(center: 1_100, language: "en", confidenceMargin: 0.8),
        ]
        let uncertain = [
            LanguageProbe(center: 200, language: "en", confidenceMargin: 0.8),
            LanguageProbe(center: 500, language: "en", confidenceMargin: 0.8),
            LanguageProbe(center: 800, language: "hi", confidenceMargin: 0.1),
            LanguageProbe(center: 1_100, language: "hi", confidenceMargin: 0.1),
        ]

        #expect(CodeSwitchChunkPlanner.plan(
            audio: audio,
            speechRanges: [0..<1_400],
            probes: noisy,
            sampleRate: sampleRate
        ).count == 1)
        #expect(CodeSwitchChunkPlanner.plan(
            audio: audio,
            speechRanges: [0..<1_400],
            probes: uncertain,
            sampleRate: sampleRate
        ).count == 1)
    }

    @Test func probesAndChunksStayBounded() {
        let ranges = CodeSwitchChunkPlanner.probeRanges(
            speechRanges: [0..<10_000],
            audioCount: 10_000,
            sampleRate: sampleRate,
            maximumProbeCount: 6
        )
        #expect(ranges.count == 6)
        #expect(ranges.allSatisfy { $0.lowerBound >= 0 && $0.upperBound <= 10_000 })

        let probes = (0..<20).map { index in
            LanguageProbe(
                center: 200 + index * 400,
                language: index.isMultiple(of: 2) ? "en" : "hi",
                confidenceMargin: 0.9
            )
        }
        let chunks = CodeSwitchChunkPlanner.plan(
            audio: [Float](repeating: 0.2, count: 10_000),
            speechRanges: [0..<10_000],
            probes: probes,
            sampleRate: sampleRate,
            maximumChunkCount: 8
        )
        #expect(chunks.count <= 8)
    }
}
