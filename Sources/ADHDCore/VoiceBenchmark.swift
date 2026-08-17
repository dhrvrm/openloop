import Foundation

public enum VoiceBenchmarkCategory: String, Codable, CaseIterable, Sendable {
    case general
    case name
    case technical
}

public struct VoiceBenchmarkSample: Codable, Equatable, Sendable {
    public let category: VoiceBenchmarkCategory
    public let reference: String
    public let hypothesis: String
    public let firstPartialMilliseconds: Double
    public let finalMilliseconds: Double

    public init(
        category: VoiceBenchmarkCategory,
        reference: String,
        hypothesis: String,
        firstPartialMilliseconds: Double,
        finalMilliseconds: Double
    ) {
        self.category = category
        self.reference = reference
        self.hypothesis = hypothesis
        self.firstPartialMilliseconds = firstPartialMilliseconds
        self.finalMilliseconds = finalMilliseconds
    }
}

public struct VoiceBenchmarkMetric: Equatable, Sendable {
    public let referenceWordCount: Int
    public let editCount: Int
    public let wordErrorRate: Double

    public init(reference: String, hypothesis: String) {
        let referenceTokens = Self.tokens(in: reference)
        let hypothesisTokens = Self.tokens(in: hypothesis)
        referenceWordCount = referenceTokens.count
        editCount = Self.editDistance(from: referenceTokens, to: hypothesisTokens)
        if referenceTokens.isEmpty {
            wordErrorRate = hypothesisTokens.isEmpty ? 0 : 1
        } else {
            wordErrorRate = Double(editCount) / Double(referenceTokens.count)
        }
    }

    private static func tokens(in text: String) -> [String] {
        var result: [String] = []
        var token = ""
        for character in text {
            if character.isLetter || character.isNumber {
                token.append(character)
            } else if !token.isEmpty {
                result.append(normalize(token))
                token = ""
            }
        }
        if !token.isEmpty { result.append(normalize(token)) }
        return result
    }

    private static func normalize(_ token: String) -> String {
        token.lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    private static func editDistance(from source: [String], to target: [String]) -> Int {
        guard !source.isEmpty else { return target.count }
        guard !target.isEmpty else { return source.count }
        var previous = Array(0...target.count)
        var current = Array(repeating: 0, count: target.count + 1)
        for sourceIndex in source.indices {
            current[0] = sourceIndex + 1
            for targetIndex in target.indices {
                let substitution = previous[targetIndex] + (source[sourceIndex] == target[targetIndex] ? 0 : 1)
                current[targetIndex + 1] = min(
                    previous[targetIndex + 1] + 1,
                    current[targetIndex] + 1,
                    substitution
                )
            }
            swap(&previous, &current)
        }
        return previous[target.count]
    }
}

public struct VoiceBenchmarkReport: Equatable, Sendable {
    public let sampleCount: Int
    public let wordErrorRate: Double?
    public let firstPartialP95Milliseconds: Double?
    public let finalP95Milliseconds: Double?
    private let categoryWordErrorRates: [VoiceBenchmarkCategory: Double]

    public init(samples: [VoiceBenchmarkSample]) {
        sampleCount = samples.count
        wordErrorRate = Self.aggregateWordErrorRate(samples)
        firstPartialP95Milliseconds = Self.nearestRankP95(
            samples.map(\.firstPartialMilliseconds)
        )
        finalP95Milliseconds = Self.nearestRankP95(samples.map(\.finalMilliseconds))
        categoryWordErrorRates = Dictionary(uniqueKeysWithValues:
            VoiceBenchmarkCategory.allCases.compactMap { category in
                let rate = Self.aggregateWordErrorRate(samples.filter { $0.category == category })
                return rate.map { (category, $0) }
            }
        )
    }

    public func wordErrorRate(for category: VoiceBenchmarkCategory) -> Double? {
        categoryWordErrorRates[category]
    }

    private static func aggregateWordErrorRate(_ samples: [VoiceBenchmarkSample]) -> Double? {
        guard !samples.isEmpty else { return nil }
        let metrics = samples.map {
            VoiceBenchmarkMetric(reference: $0.reference, hypothesis: $0.hypothesis)
        }
        let references = metrics.reduce(0) { $0 + $1.referenceWordCount }
        let edits = metrics.reduce(0) { $0 + $1.editCount }
        if references == 0 { return edits == 0 ? 0 : 1 }
        return Double(edits) / Double(references)
    }

    private static func nearestRankP95(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = max(1, Int(ceil(0.95 * Double(sorted.count))))
        return sorted[rank - 1]
    }
}
