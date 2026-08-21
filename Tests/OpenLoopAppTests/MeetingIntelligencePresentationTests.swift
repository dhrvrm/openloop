import ADHDCore
import Foundation
import Testing
@testable import OpenLoopApp

@Test func meetingBriefPresentationExposesCountsAndEvidenceLabels() throws {
    let transcript = try MeetingTranscript(
        sourceName: "meeting.m4a",
        duration: 75,
        modelIdentifier: "local",
        segments: [
            try TranscriptSegment(
                start: 65,
                end: 70,
                text: "We decided to ship Friday. Dhruv will send the notes.",
                speaker: "Speaker 2"
            ),
        ]
    )
    let brief = MeetingIntelligenceCompiler().compile(transcript)

    #expect(MeetingIntelligencePresentation.countLabel(for: brief) == "2 highlights · 0 questions · 1 decision · 1 action")
    let action = try #require(brief.actionCandidates.first)
    #expect(MeetingIntelligencePresentation.evidenceLabel(for: action) == "1:05 · Speaker 2")
}

@Test func meetingBriefPresentationHasHonestEmptyStates() {
    let empty = MeetingIntelligence(summary: [], decisions: [], actionCandidates: [])

    #expect(MeetingIntelligencePresentation.countLabel(for: empty) == "No brief yet")
    #expect(MeetingIntelligencePresentation.emptyDecisionText == "No explicit decisions found.")
    #expect(MeetingIntelligencePresentation.emptyActionText == "No explicit action candidates found.")
    #expect(MeetingIntelligencePresentation.emptyQuestionText == "No open questions found.")
}
