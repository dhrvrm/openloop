import Testing
@testable import OpenLoopApp

@Test func latencyUsesNearestRankP95() {
    var latency = CaptureLatency()
    for value in (1...100).reversed() {
        latency.record(milliseconds: Double(value))
    }

    #expect(latency.p95 == 95)
}

@Test func latencyNeedsAtLeastOneSample() {
    #expect(CaptureLatency().p95 == nil)
}
