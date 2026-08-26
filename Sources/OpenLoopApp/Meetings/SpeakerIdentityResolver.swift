import ADHDCore
import Foundation

struct SpeakerIdentityResolution: Equatable, Sendable {
    let segments: [TranscriptSegment]
    let fingerprints: [SpeakerFingerprintObservation]
}

struct SpeakerIdentityResolver: Sendable {
    let maximumCosineDistance: Float
    let minimumSeparationMargin: Float

    init(
        maximumCosineDistance: Float = 0.18,
        minimumSeparationMargin: Float = 0.04
    ) {
        self.maximumCosineDistance = maximumCosineDistance
        self.minimumSeparationMargin = minimumSeparationMargin
    }

    func resolve(
        segments: [TranscriptSegment],
        fingerprints: [LocalSpeakerFingerprint],
        history: [MeetingTranscript]
    ) throws -> SpeakerIdentityResolution {
        let profiles = historicalProfiles(history)
        var usedProfileIDs: Set<UUID> = []
        var usedAliases = Set(profiles.map(\.alias))
        var assignments: [String: (profileID: UUID, alias: String)] = [:]
        var observations: [SpeakerFingerprintObservation] = []

        for fingerprint in fingerprints {
            let candidates = profiles.filter { !usedProfileIDs.contains($0.profileID) }
                .compactMap { profile -> (HistoricalProfile, Float)? in
                    guard let distance = Self.cosineDistance(
                        fingerprint.embedding,
                        profile.centroid
                    ) else { return nil }
                    return (profile, distance)
                }
                .sorted {
                    if $0.1 != $1.1 { return $0.1 < $1.1 }
                    return $0.0.profileID.uuidString < $1.0.profileID.uuidString
                }
            let best = candidates.first
            let secondDistance = candidates.dropFirst().first?.1
            let isUnambiguous = secondDistance.map {
                $0 - (best?.1 ?? .infinity) >= minimumSeparationMargin
            } ?? true
            let identity: (profileID: UUID, alias: String)
            if let best,
               best.1 <= maximumCosineDistance,
               isUnambiguous {
                identity = (best.0.profileID, best.0.alias)
            } else {
                let alias = Self.nextAlias(excluding: usedAliases)
                identity = (UUID(), alias)
            }
            usedProfileIDs.insert(identity.profileID)
            usedAliases.insert(identity.alias)
            assignments[fingerprint.localSpeakerLabel] = identity
            observations.append(SpeakerFingerprintObservation(
                profileID: identity.profileID,
                localSpeakerLabel: fingerprint.localSpeakerLabel,
                embedding: fingerprint.embedding
            ))
        }

        let resolvedSegments = try segments.map { segment in
            guard let localLabel = segment.speaker,
                  let identity = assignments[localLabel] else { return segment }
            return try TranscriptSegment(
                id: segment.id,
                start: segment.start,
                end: segment.end,
                text: segment.text,
                speaker: identity.alias,
                speakerProfileID: identity.profileID
            )
        }
        return SpeakerIdentityResolution(
            segments: resolvedSegments,
            fingerprints: observations
        )
    }

    private func historicalProfiles(_ history: [MeetingTranscript]) -> [HistoricalProfile] {
        var embeddings: [UUID: [[Float]]] = [:]
        var aliases: [UUID: (name: String, date: Date)] = [:]
        for transcript in history {
            for observation in transcript.speakerFingerprints where !observation.embedding.isEmpty {
                embeddings[observation.profileID, default: []].append(observation.embedding)
            }
            for segment in transcript.segments {
                guard let profileID = segment.speakerProfileID,
                      let alias = segment.speaker else { continue }
                if aliases[profileID] == nil || transcript.createdAt >= aliases[profileID]!.date {
                    aliases[profileID] = (alias, transcript.createdAt)
                }
            }
        }
        return embeddings.keys.sorted { $0.uuidString < $1.uuidString }.compactMap { profileID in
            guard let vectors = embeddings[profileID],
                  let centroid = Self.centroid(vectors),
                  let alias = aliases[profileID]?.name else { return nil }
            return HistoricalProfile(profileID: profileID, alias: alias, centroid: centroid)
        }
    }

    private static func centroid(_ vectors: [[Float]]) -> [Float]? {
        guard let dimension = vectors.first?.count,
              dimension > 0 else { return nil }
        let unitVectors = vectors.compactMap(Self.normalized).filter { $0.count == dimension }
        guard !unitVectors.isEmpty else { return nil }
        var result = [Float](repeating: 0, count: dimension)
        for vector in unitVectors {
            for index in result.indices { result[index] += vector[index] }
        }
        return Self.normalized(result.map { $0 / Float(unitVectors.count) })
    }

    private static func normalized(_ vector: [Float]) -> [Float]? {
        guard !vector.isEmpty, vector.allSatisfy(\.isFinite) else { return nil }
        let magnitude = sqrt(vector.reduce(Float.zero) { $0 + $1 * $1 })
        guard magnitude > 0 else { return nil }
        return vector.map { $0 / magnitude }
    }

    private static func cosineDistance(_ left: [Float], _ right: [Float]) -> Float? {
        guard left.count == right.count,
              let lhs = normalized(left),
              let rhs = normalized(right) else { return nil }
        let similarity = zip(lhs, rhs).reduce(Float.zero) { $0 + $1.0 * $1.1 }
        return min(2, max(0, 1 - similarity))
    }

    private static func nextAlias(excluding used: Set<String>) -> String {
        var index = 0
        while used.contains(WhisperKitMeetingTranscriber.speakerLabel(index)) { index += 1 }
        return WhisperKitMeetingTranscriber.speakerLabel(index)
    }
}

private struct HistoricalProfile {
    let profileID: UUID
    let alias: String
    let centroid: [Float]
}
