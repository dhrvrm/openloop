import ADHDCore
import Foundation
import Testing
@testable import OpenLoopApp

@Test func localMeetingIntelligenceAcceptsParaphraseWithExactEvidence() async throws {
    let segment = try TranscriptSegment(
        id: UUID(uuidString: "A1A1A1A1-A1A1-4A1A-A1A1-A1A1A1A1A1A1")!,
        start: 12,
        end: 19,
        text: "Release time कम करना है. Can we automate the SGLC checks?",
        speaker: "Dhruv"
    )
    let transcript = try MeetingTranscript(
        sourceName: "mixed-language.m4a",
        duration: 19,
        modelIdentifier: "test-stt",
        segments: [segment]
    )
    let response = """
    {
      "summary": [{
        "text": "The team wants to shorten release time.",
        "segment_id": "\(segment.id.uuidString)",
        "evidence_excerpt": "Release time कम करना है.",
        "confidence": 0.93
      }],
      "questions": [{
        "text": "Can the SGLC checks be automated?",
        "segment_id": "\(segment.id.uuidString)",
        "evidence_excerpt": "Can we automate the SGLC checks?",
        "confidence": 0.98
      }],
      "decisions": [],
      "action_candidates": []
    }
    """
    let provider = LocalMeetingIntelligenceProvider { _, _ in response }

    let record = try await provider.interpret(transcript)

    #expect(record.providerIdentifier == LocalMeetingIntelligenceProvider.providerIdentifier)
    #expect(record.modelIdentifier == LocalMeetingIntelligenceProvider.modelIdentifier)
    #expect(record.intelligence.summary.first?.text == "The team wants to shorten release time.")
    #expect(record.intelligence.summary.first?.evidence.excerpt == "Release time कम करना है.")
    #expect(record.intelligence.questions.first?.evidence.segmentID == segment.id)
}

@Test func localMeetingIntelligenceRejectsInventedEvidenceAndFallsBack() async throws {
    let segment = try TranscriptSegment(
        start: 0,
        end: 5,
        text: "Maybe we should inspect the release pipeline."
    )
    let transcript = try MeetingTranscript(
        sourceName: "meeting.m4a",
        duration: 5,
        modelIdentifier: "test-stt",
        segments: [segment]
    )
    let response = """
    {
      "summary": [{
        "text": "The deployment is broken.",
        "segment_id": "\(segment.id.uuidString)",
        "evidence_excerpt": "The deployment is broken.",
        "confidence": 0.99
      }],
      "questions": [],
      "decisions": [],
      "action_candidates": []
    }
    """
    let provider = LocalMeetingIntelligenceProvider { _, _ in response }

    let record = try await provider.interpret(transcript)

    #expect(record.providerIdentifier == "openloop.extractive")
    #expect(record.modelIdentifier == "meeting-compiler-v1")
    #expect(record.intelligence.summary.allSatisfy {
        segment.text.contains($0.evidence.excerpt)
    })
}

@Test func localMeetingIntelligenceFallsBackWhenModelReturnsNonJSON() async throws {
    let segment = try TranscriptSegment(start: 0, end: 3, text: "We decided to ship Friday.")
    let transcript = try MeetingTranscript(
        sourceName: "meeting.m4a",
        duration: 3,
        modelIdentifier: "test-stt",
        segments: [segment]
    )
    let provider = LocalMeetingIntelligenceProvider { _, _ in
        "I cannot produce structured output."
    }

    let record = try await provider.interpret(transcript)

    #expect(record.providerIdentifier == "openloop.extractive")
    #expect(record.intelligence.decisions.first?.text == "We decided to ship Friday.")
}
