import ADHDCore
import Foundation
import Testing
@testable import OpenLoopApp

@Suite("meeting title naming")
struct MeetingTitleNamingTests {
    @Test func normalizesModelOutputWithoutChangingMeaning() {
        #expect(MeetingTitleNaming.displayTitle("  Title: **Checkout latency.**  ") == "Checkout latency")
        #expect(MeetingTitleNaming.displayTitle("\n\"संग्रहालय onboarding\"\n") == "संग्रहालय onboarding")
    }

    @Test func datedFileNameIncludesSubjectAndCaptureTime() {
        let date = Date(timeIntervalSince1970: 0)
        let zone = TimeZone(secondsFromGMT: 0)!
        #expect(MeetingTitleNaming.fileName(
            title: "Checkout latency",
            createdAt: date,
            fileExtension: "M4A",
            timeZone: zone
        ) == "1970-01-01_0000-checkout-latency.m4a")
    }

    @Test func fallbackUsesTheFirstGroundedThought() throws {
        let transcript = try MeetingTranscript(
            sourceName: "recording.m4a",
            duration: 4,
            modelIdentifier: "fixture",
            segments: [try TranscriptSegment(start: 0, end: 4, text: "Plan the gallery visitor test. Ignore this later sentence.")]
        )
        #expect(MeetingTitleNaming.fallbackTitle(for: transcript) == "Plan the gallery visitor test")
        #expect(MeetingTitleNaming.needsHumanTitle("recording.m4a"))
        #expect(MeetingTitleNaming.needsHumanTitle("Gallery visitor test") == false)
        #expect(MeetingTitleNaming.needsHumanTitle("Dr. Mehta interview") == false)
    }
}
