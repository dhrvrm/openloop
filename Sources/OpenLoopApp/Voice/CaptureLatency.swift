import Foundation

struct CaptureLatency {
    private(set) var samples: [Double] = []

    mutating func record(milliseconds: Double) { samples.append(milliseconds) }

    var p95: Double? {
        guard samples.isEmpty == false else { return nil }
        let sorted = samples.sorted()
        let rank = Int(ceil(Double(sorted.count) * 0.95))
        return sorted[max(0, rank - 1)]
    }
}
