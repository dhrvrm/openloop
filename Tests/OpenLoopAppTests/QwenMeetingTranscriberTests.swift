import Foundation
import Testing
@testable import OpenLoopApp

@Test func qwenVocabularyContextIsBoundedDeduplicatedAndOptional() {
    #expect(QwenMeetingTranscriber.context(from: []) == nil)
    #expect(QwenMeetingTranscriber.context(from: [
        " SGLC ",
        "sglc",
        "Redis",
        "",
    ]) == "Vocabulary and names: SGLC, Redis")
    #expect(QwenMeetingTranscriber.context(from: ["one", "two", "three"], limit: 2)
        == "Vocabulary and names: one, two")
}

@Test func qwenTokenBudgetTracksDurationWithinModelLimits() {
    #expect(QwenMeetingTranscriber.maximumTokens(for: 0) == 64)
    #expect(QwenMeetingTranscriber.maximumTokens(for: 10) == 180)
    #expect(QwenMeetingTranscriber.maximumTokens(for: 3_600) == 448)
}

@Test func qwenLanguageSummaryRecognizesHinglishWithoutAUserPrompt() {
    #expect(QwenMeetingTranscriber.spokenLanguageSummary(
        text: "Release time क्या हम कम कर सकते हैं?",
        requested: nil
    ) == "en + hi")
    #expect(QwenMeetingTranscriber.spokenLanguageSummary(
        text: "हम कम कर सकते हैं",
        requested: nil
    ) == "hi")
    #expect(QwenMeetingTranscriber.spokenLanguageSummary(
        text: "Can we reduce it?",
        requested: nil
    ) == "en")
}
