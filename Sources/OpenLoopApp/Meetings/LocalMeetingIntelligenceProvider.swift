import ADHDCore
import Foundation
import Qwen3Chat

actor LocalMeetingIntelligenceProvider: MeetingIntelligenceProviding {
    typealias Generator = @Sendable (_ system: String, _ user: String) async throws -> String

    static let providerIdentifier = "openloop.local-qwen"
    static let modelIdentifier = "qwen3.5-mlx-int4"

    private let generator: Generator
    private let fallback: any MeetingIntelligenceProviding

    init(fallback: any MeetingIntelligenceProviding = DeterministicMeetingIntelligenceProvider()) {
        let runtime = QwenMeetingIntelligenceRuntime()
        generator = { system, user in
            try await runtime.generate(system: system, user: user)
        }
        self.fallback = fallback
    }

    init(
        generator: @escaping Generator,
        fallback: any MeetingIntelligenceProviding = DeterministicMeetingIntelligenceProvider()
    ) {
        self.generator = generator
        self.fallback = fallback
    }

    func interpret(_ transcript: MeetingTranscript) async throws -> MeetingInterpretationRecord {
        do {
            var drafts: [DraftResponse] = []
            for chunk in Self.chunks(transcript.segments) {
                let response = try await generator(Self.systemPrompt, Self.userPrompt(for: chunk))
                drafts.append(try Self.decode(response))
            }
            let intelligence = try Self.intelligence(from: drafts, transcript: transcript)
            guard !Self.allInsights(in: intelligence).isEmpty else {
                return try await fallback.interpret(transcript)
            }
            return try MeetingInterpretationRecord(
                transcript: transcript,
                providerIdentifier: Self.providerIdentifier,
                modelIdentifier: Self.modelIdentifier,
                intelligence: intelligence
            )
        } catch {
            return try await fallback.interpret(transcript)
        }
    }
}

extension LocalMeetingIntelligenceProvider: MeetingTitleProviding {
    func title(for transcript: MeetingTranscript) async -> String {
        let fallback = MeetingTitleNaming.fallbackTitle(for: transcript)
        do {
            let response = try await generator(
                Self.titleSystemPrompt,
                Self.titleUserPrompt(for: transcript)
            )
            let title = MeetingTitleNaming.displayTitle(response)
            return title == "Voice note" ? fallback : title
        } catch {
            return fallback
        }
    }
}

private actor QwenMeetingIntelligenceRuntime {
    private var model: Qwen35MLXChat?

    func generate(system: String, user: String) async throws -> String {
        let model = try await loadedModel()
        return try model.generate(
            messages: [
                ChatMessage(role: .system, content: system),
                ChatMessage(role: .user, content: user),
            ],
            sampling: ChatSamplingConfig(
                temperature: 0.1,
                topK: 20,
                topP: 0.8,
                maxTokens: 1_536,
                repetitionPenalty: 1.05
            )
        )
    }

    private func loadedModel() async throws -> Qwen35MLXChat {
        if let model { return model }
        let loaded = try await Qwen35MLXChat.fromPretrained(quantization: .int4)
        model = loaded
        return loaded
    }
}

private extension LocalMeetingIntelligenceProvider {
    enum ResponseError: Error {
        case invalidJSON
        case unknownSegment
        case ungroundedEvidence
        case invalidConfidence
    }

    struct DraftResponse: Decodable {
        let summary: [DraftInsight]
        let questions: [DraftInsight]
        let decisions: [DraftInsight]
        let actionCandidates: [DraftInsight]

        enum CodingKeys: String, CodingKey {
            case summary
            case questions
            case decisions
            case actionCandidates = "action_candidates"
        }
    }

    struct DraftInsight: Decodable {
        let text: String
        let segmentID: String
        let evidenceExcerpt: String
        let confidence: Double

        enum CodingKeys: String, CodingKey {
            case text
            case segmentID = "segment_id"
            case evidenceExcerpt = "evidence_excerpt"
            case confidence
        }
    }

    static let systemPrompt = """
    You extract a concise meeting brief from a private transcript. Return JSON only.
    Preserve Hindi, Hinglish, English, names, acronyms, uncertainty, and negation.
    Never invent a fact. Every item must cite one segment_id from the input and an
    evidence_excerpt copied exactly and contiguously from that segment. A summary
    may compress meaning, but its evidence must still be verbatim. Do not turn a
    possibility into a decision or a suggestion into an assigned action.

    Return exactly this shape:
    {"summary":[{"text":"...","segment_id":"UUID","evidence_excerpt":"exact quote","confidence":0.0}],"questions":[],"decisions":[],"action_candidates":[]}
    Use no more than 4 summary items and 5 items in each other collection.
    """

    static let titleSystemPrompt = """
    Name a private voice recording from its actual subject. Return only a short title,
    without quotes, labels, punctuation, dates, or commentary. Use 3 to 8 words when
    the transcript supports them. Preserve the language and spelling used by the
    speaker. Never invent a project, person, decision, or topic.
    """

    static func titleUserPrompt(for transcript: MeetingTranscript) -> String {
        "TRANSCRIPT:\n\(String(transcript.text.prefix(6_000)))"
    }

    static func userPrompt(for segments: [TranscriptSegment]) -> String {
        let encoded = segments.map { segment in
            let boundedText = String(segment.text.prefix(11_500))
            return "SEGMENT \(segment.id.uuidString) [\(Self.timestamp(segment.start))]\n\(boundedText)"
        }.joined(separator: "\n\n")
        return "TRANSCRIPT SEGMENTS:\n\n\(encoded)"
    }

    static func chunks(_ segments: [TranscriptSegment], limit: Int = 12_000)
        -> [[TranscriptSegment]] {
        var result: [[TranscriptSegment]] = []
        var current: [TranscriptSegment] = []
        var count = 0
        for segment in segments {
            let size = min(segment.text.count, limit) + 80
            if !current.isEmpty, count + size > limit {
                result.append(current)
                current = []
                count = 0
            }
            current.append(segment)
            count += size
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    static func decode(_ raw: String) throws -> DraftResponse {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```") {
            let lines = value.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count >= 3, lines.last?.trimmingCharacters(in: .whitespaces) == "```" {
                value = lines.dropFirst().dropLast().joined(separator: "\n")
            }
        }
        guard let start = value.firstIndex(of: "{"),
              let end = value.lastIndex(of: "}"),
              start <= end,
              let data = String(value[start...end]).data(using: .utf8)
        else { throw ResponseError.invalidJSON }
        do {
            return try JSONDecoder().decode(DraftResponse.self, from: data)
        } catch {
            throw ResponseError.invalidJSON
        }
    }

    static func intelligence(from drafts: [DraftResponse], transcript: MeetingTranscript) throws
        -> MeetingIntelligence {
        let segments = Dictionary(uniqueKeysWithValues: transcript.segments.map { ($0.id, $0) })
        let summary = try insights(
            drafts.flatMap(\.summary), kind: .summary, segments: segments, maximum: 8
        )
        let questions = try insights(
            drafts.flatMap(\.questions), kind: .question, segments: segments, maximum: 10
        )
        let decisions = try insights(
            drafts.flatMap(\.decisions), kind: .decision, segments: segments, maximum: 10
        )
        let actions = try insights(
            drafts.flatMap(\.actionCandidates),
            kind: .actionCandidate,
            segments: segments,
            maximum: 12
        )
        return MeetingIntelligence(
            summary: summary,
            questions: questions,
            decisions: decisions,
            actionCandidates: actions
        )
    }

    static func insights(
        _ drafts: [DraftInsight],
        kind: MeetingInsightKind,
        segments: [UUID: TranscriptSegment],
        maximum: Int
    ) throws -> [MeetingInsight] {
        var seen: Set<String> = []
        var result: [MeetingInsight] = []
        for draft in drafts {
            let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let excerpt = draft.evidenceExcerpt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !excerpt.isEmpty else { continue }
            guard let segmentID = UUID(uuidString: draft.segmentID),
                  let segment = segments[segmentID]
            else { throw ResponseError.unknownSegment }
            guard segment.text.contains(excerpt) else { throw ResponseError.ungroundedEvidence }
            guard draft.confidence.isFinite, (0...1).contains(draft.confidence) else {
                throw ResponseError.invalidConfidence
            }
            let key = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            guard seen.insert(key).inserted else { continue }
            result.append(MeetingInsight(
                id: "local-\(kind.rawValue)-\(segmentID.uuidString)-\(result.count)",
                kind: kind,
                text: text,
                evidence: MeetingEvidence(
                    segmentID: segmentID,
                    start: segment.start,
                    speaker: segment.speaker,
                    excerpt: excerpt
                ),
                confidence: draft.confidence
            ))
            if result.count == maximum { break }
        }
        return result
    }

    static func allInsights(in intelligence: MeetingIntelligence) -> [MeetingInsight] {
        intelligence.summary + intelligence.questions + intelligence.decisions
            + intelligence.actionCandidates
    }

    static func timestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
