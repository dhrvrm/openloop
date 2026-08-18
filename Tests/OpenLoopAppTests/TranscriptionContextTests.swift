import Testing
@testable import OpenLoopApp

@Suite struct TranscriptionContextTests {
    @Test func includesLocalNameAndCodeSwitchingVocabulary() {
        let value = TranscriptionContext.make(localUserName: "  Dhruv   Sharma  ")

        #expect(value.contains("Participants: Dhruv Sharma."))
        #expect(value.contains("English"))
        #expect(value.contains("Hindi"))
        #expect(value.contains("Hinglish"))
        #expect(value.contains("do not translate"))
    }

    @Test func omitsBlankLocalName() {
        let value = TranscriptionContext.make(localUserName: " \n\t ")

        #expect(!value.contains("Participants:"))
        #expect(value.hasPrefix("Multilingual conversation"))
    }

    @Test func limitsAccountNameContext() {
        let value = TranscriptionContext.make(localUserName: String(repeating: "D", count: 200))
        let participant = value
            .split(separator: ".", maxSplits: 1)
            .first
            .map(String.init) ?? ""

        #expect(participant.count == "Participants: ".count + 80)
    }
}
