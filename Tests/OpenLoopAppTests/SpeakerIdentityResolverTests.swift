import ADHDCore
import Foundation
import Testing
@testable import OpenLoopApp

@Test func newVoicesReceiveAlphabeticProfiles() throws {
    let segments = [
        try TranscriptSegment(start: 0, end: 1, text: "one", speaker: "Speaker A"),
        try TranscriptSegment(start: 1, end: 2, text: "two", speaker: "Speaker B"),
    ]
    let result = try SpeakerIdentityResolver().resolve(
        segments: segments,
        fingerprints: [
            LocalSpeakerFingerprint(localSpeakerLabel: "Speaker A", embedding: [1, 0]),
            LocalSpeakerFingerprint(localSpeakerLabel: "Speaker B", embedding: [0, 1]),
        ],
        history: []
    )

    #expect(result.segments.map(\.speaker) == ["Speaker A", "Speaker B"])
    #expect(Set(result.segments.compactMap(\.speakerProfileID)).count == 2)
    #expect(result.fingerprints.count == 2)
}

@Test func knownVoiceReusesItsProfileAndAlias() throws {
    let profileID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!
    let history = [try identityTranscript(
        profileID: profileID,
        alias: "Dhruv",
        embedding: [1, 0]
    )]
    let result = try SpeakerIdentityResolver().resolve(
        segments: [try TranscriptSegment(
            start: 0, end: 1, text: "hello", speaker: "Speaker A"
        )],
        fingerprints: [LocalSpeakerFingerprint(
            localSpeakerLabel: "Speaker A", embedding: [0.999, 0.01]
        )],
        history: history
    )

    #expect(result.segments[0].speaker == "Dhruv")
    #expect(result.segments[0].speakerProfileID == profileID)
}

@Test func ambiguousVoiceDoesNotStealAnExistingIdentity() throws {
    let first = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!
    let second = UUID(uuidString: "00000000-0000-0000-0000-0000000000D2")!
    let history = [
        try identityTranscript(profileID: first, alias: "Dhruv", embedding: [1, 0]),
        try identityTranscript(profileID: second, alias: "Kuvam", embedding: [0.999, 0.03]),
    ]
    let result = try SpeakerIdentityResolver().resolve(
        segments: [try TranscriptSegment(
            start: 0, end: 1, text: "hello", speaker: "Speaker A"
        )],
        fingerprints: [LocalSpeakerFingerprint(
            localSpeakerLabel: "Speaker A", embedding: [1, 0.01]
        )],
        history: history
    )

    #expect(result.segments[0].speaker == "Speaker A")
    #expect(result.segments[0].speakerProfileID != first)
    #expect(result.segments[0].speakerProfileID != second)
}

private func identityTranscript(
    profileID: UUID,
    alias: String,
    embedding: [Float]
) throws -> MeetingTranscript {
    try MeetingTranscript(
        sourceName: "history.wav",
        duration: 1,
        modelIdentifier: "local",
        segments: [try TranscriptSegment(
            start: 0,
            end: 1,
            text: "history",
            speaker: alias,
            speakerProfileID: profileID
        )],
        speakerSeparation: .complete(speakerCount: 1),
        speakerFingerprints: [SpeakerFingerprintObservation(
            profileID: profileID,
            localSpeakerLabel: "Speaker A",
            embedding: embedding
        )]
    )
}
