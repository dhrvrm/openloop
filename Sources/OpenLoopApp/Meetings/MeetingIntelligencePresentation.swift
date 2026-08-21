import ADHDCore
import Foundation

enum MeetingIntelligencePresentation {
    static let emptyDecisionText = "No explicit decisions found."
    static let emptyActionText = "No explicit action candidates found."
    static let emptyQuestionText = "No open questions found."

    static func countLabel(for intelligence: MeetingIntelligence) -> String {
        let highlights = intelligence.summary.count
        let questions = intelligence.questions.count
        let decisions = intelligence.decisions.count
        let actions = intelligence.actionCandidates.count
        guard highlights + questions + decisions + actions > 0 else { return "No brief yet" }
        return "\(highlights) \(noun(highlights, singular: "highlight")) · "
            + "\(questions) \(noun(questions, singular: "question")) · "
            + "\(decisions) \(noun(decisions, singular: "decision")) · "
            + "\(actions) \(noun(actions, singular: "action"))"
    }

    static func evidenceLabel(for insight: MeetingInsight) -> String {
        let total = max(0, Int(insight.evidence.start))
        let timestamp = total >= 3_600
            ? String(format: "%d:%02d:%02d", total / 3_600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
        guard let speaker = insight.evidence.speaker else { return timestamp }
        return "\(timestamp) · \(speaker)"
    }

    private static func noun(_ count: Int, singular: String) -> String {
        count == 1 ? singular : "\(singular)s"
    }
}
