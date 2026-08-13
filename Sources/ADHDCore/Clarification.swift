import Foundation

public enum Disposition: String, Codable, Equatable, Sendable {
    case action
    case memory
    case later
    case release
    case unclear
}

public enum ClarificationError: Error, Equatable {
    case actionRequiresNextStep
    case invalidConfidence
}

public struct ClarificationProposal: Codable, Equatable, Sendable {
    public let captureID: UUID
    public let disposition: Disposition
    public let desiredOutcome: String?
    public let nextAction: String?
    public let confidence: Double

    public init(
        captureID: UUID,
        disposition: Disposition,
        desiredOutcome: String?,
        nextAction: String?,
        confidence: Double
    ) throws {
        guard (0...1).contains(confidence) else {
            throw ClarificationError.invalidConfidence
        }

        let normalizedOutcome = desiredOutcome?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAction = nextAction?.trimmingCharacters(in: .whitespacesAndNewlines)
        if disposition == .action {
            guard normalizedOutcome?.isEmpty == false, normalizedAction?.isEmpty == false else {
                throw ClarificationError.actionRequiresNextStep
            }
        }

        self.captureID = captureID
        self.disposition = disposition
        self.desiredOutcome = normalizedOutcome
        self.nextAction = normalizedAction
        self.confidence = confidence
    }
}
