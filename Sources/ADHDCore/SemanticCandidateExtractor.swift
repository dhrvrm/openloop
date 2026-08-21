import Foundation

public struct SemanticCandidate: Equatable, Sendable {
    public let kind: SemanticNodeKind
    public let claim: String
    public let confidence: Double
    public let status: SemanticNodeStatus

    public init(
        kind: SemanticNodeKind,
        claim: String,
        confidence: Double,
        status: SemanticNodeStatus
    ) {
        self.kind = kind
        self.claim = claim
        self.confidence = confidence
        self.status = status
    }
}

/// Extracts only directly evidenced meaning from an utterance. It keeps the
/// original sentence as the claim so every candidate remains auditable and
/// treats uncertain language as possibility, never as a decision or action.
public struct SemanticCandidateExtractor: Sendable {
    public init() {}

    public func extract(from text: String) -> [SemanticCandidate] {
        Self.sentences(in: text).compactMap(Self.candidate)
    }
}

private extension SemanticCandidateExtractor {
    static let uncertaintyMarkers = [
        "maybe", "perhaps", "might", "may ", "possibly", "शायद", "हो सकता",
        "हो सकती", "हो सकते", "shayad", "ho sakta", "ho sakti", "ho sakte",
    ]
    static let decisionMarkers = [
        "decision:", "we decided", "i decided", "it was decided", "we agreed",
        "i chose", "we chose", "finalized", "finalised", "तय किया", "तय हुआ",
        "फैसला", "निर्णय", "सहमति", "decide kiya", "tay kiya", "final hai",
    ]
    static let intentionMarkers = [
        "action item:", "todo:", "follow up:", "follow-up:", "i will ",
        "i'll ", "i’ll ", "we will ", "we'll ", "we’ll ", "करना है",
        "भेजना है", "बनाना है", "देखना है", "बतना है", "karna hai",
        "bhejna hai", "banana hai", "dekhna hai",
    ]
    static let ideaMarkers = [
        "we should ", "i should ", "let's ", "lets ", "why don't we ",
        "कैसा रहेगा", "कर सकते हैं", "कर सकते है", "करना चाहिए",
        "kar sakte hain", "karna chahiye",
    ]
    static let problemMarkers = [
        " problem", "problem ", " issue", "issue ", " bug", "bug ", "broken",
        "failing", "failure", "crash", "crashed", "slow", "slower", "latency",
        "wrong", "inaccurate", "unreliable", "blocked", "समस्या", "दिक्कत",
        "गलत", "धीमा", "धीमी", "क्रैश", "नहीं चल", "nahi chal", "dikkat",
        "galat", "slow hai",
    ]
    static let preferenceMarkers = [
        "i prefer", "we prefer", "i like", "i don't want", "i do not want",
        "मुझे पसंद", "मैं चाहता", "मैं चाहती", "mujhe pasand", "main chahta",
        "main chahti",
    ]

    static func candidate(_ sentence: String) -> SemanticCandidate? {
        let searchable = " \(sentence.lowercased()) "
        if isQuestion(sentence, searchable: searchable) {
            return SemanticCandidate(
                kind: .question,
                claim: sentence,
                confidence: 0.98,
                status: .active
            )
        }
        if containsAny(uncertaintyMarkers, in: searchable) {
            return SemanticCandidate(
                kind: .possibility,
                claim: sentence,
                confidence: 0.9,
                status: .speculative
            )
        }
        if containsAny(decisionMarkers, in: searchable) {
            return SemanticCandidate(
                kind: .decision,
                claim: sentence,
                confidence: 0.96,
                status: .active
            )
        }
        if containsAny(intentionMarkers, in: searchable) || hasFutureCommitment(searchable) {
            return SemanticCandidate(
                kind: .intention,
                claim: sentence,
                confidence: 0.94,
                status: .active
            )
        }
        if containsAny(problemMarkers, in: searchable) {
            return SemanticCandidate(
                kind: .problem,
                claim: sentence,
                confidence: 0.86,
                status: .active
            )
        }
        if containsAny(preferenceMarkers, in: searchable) {
            return SemanticCandidate(
                kind: .preference,
                claim: sentence,
                confidence: 0.9,
                status: .active
            )
        }
        if containsAny(ideaMarkers, in: searchable) {
            return SemanticCandidate(
                kind: .idea,
                claim: sentence,
                confidence: 0.82,
                status: .speculative
            )
        }
        return nil
    }

    static func sentences(in text: String) -> [String] {
        var values: [String] = []
        var buffer = ""
        func flush() {
            let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { values.append(value) }
            buffer = ""
        }
        for character in text {
            buffer.append(character)
            if character == "." || character == "!" || character == "?"
                || character == "।" || character == "\n" {
                flush()
            }
        }
        flush()
        return values
    }

    static func isQuestion(_ sentence: String, searchable: String) -> Bool {
        if sentence.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?") {
            return true
        }
        let first = tokens(in: searchable).first
        let starts: Set<String> = [
            "what", "when", "where", "who", "why", "how", "can", "could",
            "would", "should", "will", "is", "are", "do", "does", "did",
            "क्या", "कब", "कौन", "कहाँ", "कैसे", "क्यों", "kya", "kab",
            "kaun", "kahan", "kaise", "kyun",
        ]
        return first.map(starts.contains) ?? false
    }

    static func containsAny(_ markers: [String], in value: String) -> Bool {
        markers.contains { value.contains($0) }
    }

    static func hasFutureCommitment(_ value: String) -> Bool {
        let suffixes = [
            "करूंगा", "करूँगा", "करूंगी", "करूँगी", "करेंगे", "भेजूंगा",
            "भेजूँगा", "भेजूंगी", "भेजूँगी", "भेजेंगे", "बनाऊंगा", "बनाऊँगा",
            "बनाऊंगी", "बनाऊँगी", "बनाएंगे", "karunga", "karungi", "karenge",
            "bhejunga", "bhejungi", "bhejenge",
        ]
        return tokens(in: value).contains { token in suffixes.contains(token) }
    }

    static func tokens(in value: String) -> [String] {
        value.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
