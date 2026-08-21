import Foundation
import Testing
@testable import ADHDCore

@Test func meetingIntelligenceBuildsEvidenceLinkedMultilingualBrief() throws {
    let transcript = try MeetingTranscript(
        sourceName: "planning.m4a",
        duration: 42,
        detectedLanguage: "en + hi",
        modelIdentifier: "local-model",
        segments: [
            try segment(
                1,
                start: 0,
                text: "Hello team. We decided to ship the offline build on Friday.",
                speaker: "Speaker 1"
            ),
            try segment(
                2,
                start: 12,
                text: "Dhruv will send the release notes tomorrow.",
                speaker: "Speaker 2"
            ),
            try segment(
                3,
                start: 24,
                text: "हिंदी वाला onboarding flow final है। मीरा कल तक screenshots भेजेगी।",
                speaker: "Speaker 1"
            ),
        ]
    )

    let brief = MeetingIntelligenceCompiler().compile(transcript)

    #expect(!brief.summary.isEmpty)
    #expect(brief.summary.count <= 3)
    #expect(brief.decisions.map(\.text).contains("We decided to ship the offline build on Friday."))
    #expect(brief.decisions.map(\.text).contains("हिंदी वाला onboarding flow final है।"))
    #expect(brief.actionCandidates.map(\.text).contains("Dhruv will send the release notes tomorrow."))
    #expect(brief.actionCandidates.map(\.text).contains("मीरा कल तक screenshots भेजेगी।"))
    #expect((brief.summary + brief.questions + brief.decisions + brief.actionCandidates).allSatisfy { insight in
        transcript.segments.contains { segment in
            segment.id == insight.evidence.segmentID
                && segment.text.contains(insight.text)
                && insight.evidence.excerpt == insight.text
        }
    })
}

@Test func meetingIntelligenceRejectsSpeculationQuestionsAndNegatedCommitments() throws {
    let transcript = try MeetingTranscript(
        sourceName: "uncertain.m4a",
        duration: 20,
        modelIdentifier: "local-model",
        segments: [
            try segment(10, start: 0, text: "Could we send it tomorrow?"),
            try segment(11, start: 4, text: "Maybe Riya will prepare the deck."),
            try segment(12, start: 8, text: "We will not publish this build."),
            try segment(13, start: 12, text: "Please review the screen."),
            try segment(14, start: 16, text: "क्या हम इसे कल भेजेंगे?"),
            try segment(15, start: 18, text: "Have we decided to publish?"),
            try segment(16, start: 19, text: "Maybe we decided to publish."),
            try segment(17, start: 20, text: "The integration will send telemetry automatically."),
            try segment(18, start: 21, text: "Have we decided to publish"),
            try segment(19, start: 22, text: "Maybe, we decided to publish."),
            try segment(20, start: 23, text: "Rain will continue tomorrow."),
            try segment(21, start: 24, text: "Nothing will change next week."),
            try segment(22, start: 25, text: "Customer demand will increase."),
            try segment(23, start: 26, text: "He will be late."),
            try segment(24, start: 27, text: "Maybe, I will send the notes."),
            try segment(25, start: 28, text: "Perhaps, we will publish the build."),
            try segment(26, start: 29, text: "Maybe, action item: send the release notes."),
        ]
    )

    let brief = MeetingIntelligenceCompiler().compile(transcript)

    #expect(brief.decisions.isEmpty)
    #expect(brief.actionCandidates.isEmpty)
    #expect(brief.questions.count == 4)
    #expect(brief.questions.map(\.text).contains("क्या हम इसे कल भेजेंगे?"))
}

@Test func meetingIntelligenceIsDeterministicAndDeduplicatesSummary() throws {
    let transcript = try MeetingTranscript(
        sourceName: "repeat.m4a",
        duration: 30,
        modelIdentifier: "local-model",
        segments: [
            try segment(20, start: 0, text: "The launch plan covers the local model and release."),
            try segment(21, start: 5, text: "The launch plan covers the local model and release."),
            try segment(22, start: 10, text: "Customer testing starts after the local release."),
            try segment(23, start: 15, text: "We decided to keep all audio on this Mac."),
        ]
    )
    let compiler = MeetingIntelligenceCompiler()

    let first = compiler.compile(transcript)
    let second = compiler.compile(transcript)

    #expect(first == second)
    #expect(Set(first.summary.map(\.text)).count == first.summary.count)
    #expect(first.summary.map(\.id) == second.summary.map(\.id))
}

@Test func meetingInsightCarriesTimestampSpeakerAndStableIdentity() throws {
    let source = try segment(
        30,
        start: 61.5,
        text: "Action item: send the bilingual transcript.",
        speaker: "Speaker 3"
    )
    let transcript = try MeetingTranscript(
        sourceName: "evidence.m4a",
        duration: 70,
        modelIdentifier: "local-model",
        segments: [source]
    )

    let item = try #require(MeetingIntelligenceCompiler().compile(transcript).actionCandidates.first)

    #expect(item.id == "actionCandidate:\(source.id.uuidString):0")
    #expect(item.evidence.start == 61.5)
    #expect(item.evidence.speaker == "Speaker 3")
    #expect(item.evidence.excerpt == "Action item: send the bilingual transcript.")
}

private func segment(
    _ suffix: Int,
    start: TimeInterval,
    text: String,
    speaker: String? = nil
) throws -> TranscriptSegment {
    try TranscriptSegment(
        id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!,
        start: start,
        end: start + 4,
        text: text,
        speaker: speaker
    )
}
