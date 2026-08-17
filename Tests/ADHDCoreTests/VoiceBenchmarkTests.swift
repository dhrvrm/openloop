import Foundation
import Testing
@testable import ADHDCore

@Test func voiceBenchmarkMetricComputesExactWordErrors() {
    let exact = VoiceBenchmarkMetric(reference: "Open Xcode", hypothesis: "open xcode!")
    let substitution = VoiceBenchmarkMetric(reference: "Open Xcode", hypothesis: "open code")
    let insertion = VoiceBenchmarkMetric(reference: "open xcode", hypothesis: "please open xcode")
    let deletion = VoiceBenchmarkMetric(reference: "please open xcode", hypothesis: "open xcode")

    #expect(exact.wordErrorRate == 0)
    #expect(substitution.referenceWordCount == 2)
    #expect(substitution.editCount == 1)
    #expect(substitution.wordErrorRate == 0.5)
    #expect(insertion.editCount == 1)
    #expect(deletion.editCount == 1)
    #expect(VoiceBenchmarkMetric(reference: "", hypothesis: "").wordErrorRate == 0)
    #expect(VoiceBenchmarkMetric(reference: "", hypothesis: "unexpected").wordErrorRate == 1)
}

@Test func voiceBenchmarkReportUsesMicroAverageNearestRankAndCategories() {
    let samples = [
        VoiceBenchmarkSample(
            category: .general, reference: "capture this thought", hypothesis: "capture this thought",
            firstPartialMilliseconds: 40, finalMilliseconds: 100
        ),
        VoiceBenchmarkSample(
            category: .name, reference: "call Kuvam", hypothesis: "call cool van",
            firstPartialMilliseconds: 80, finalMilliseconds: 200
        ),
        VoiceBenchmarkSample(
            category: .technical, reference: "open Xcode", hypothesis: "open code",
            firstPartialMilliseconds: 60, finalMilliseconds: 150
        ),
    ]

    let report = VoiceBenchmarkReport(samples: samples)

    #expect(report.sampleCount == 3)
    #expect(report.wordErrorRate == 3.0 / 7.0)
    #expect(report.firstPartialP95Milliseconds == 80)
    #expect(report.finalP95Milliseconds == 200)
    #expect(report.wordErrorRate(for: .general) == 0)
    #expect(report.wordErrorRate(for: .name) == 1)
    #expect(report.wordErrorRate(for: .technical) == 0.5)
}

@Test func emptyVoiceBenchmarkReportIsExplicitlyEmpty() {
    let report = VoiceBenchmarkReport(samples: [])

    #expect(report.sampleCount == 0)
    #expect(report.wordErrorRate == nil)
    #expect(report.firstPartialP95Milliseconds == nil)
    #expect(report.finalP95Milliseconds == nil)
    #expect(report.wordErrorRate(for: .general) == nil)
}

@Test func mixedVoiceBenchmarkFixtureProducesDocumentedMetrics() throws {
    let testFile = URL(fileURLWithPath: #filePath)
    let fixture = testFile.deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/voice-benchmark.json")
    let samples = try JSONDecoder().decode(
        [VoiceBenchmarkSample].self,
        from: Data(contentsOf: fixture)
    )
    let report = VoiceBenchmarkReport(samples: samples)

    #expect(report.sampleCount == 3)
    #expect(report.wordErrorRate == 3.0 / 7.0)
    #expect(report.firstPartialP95Milliseconds == 80)
    #expect(report.finalP95Milliseconds == 200)
    #expect(report.wordErrorRate(for: .general) == 0)
    #expect(report.wordErrorRate(for: .name) == 1)
    #expect(report.wordErrorRate(for: .technical) == 0.5)
}
