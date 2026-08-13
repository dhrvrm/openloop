import ADHDCore
import Foundation

public struct RuleClarificationProvider: ClarificationProvider {
    public init() {}

    public func propose(for capture: RawCapture) async throws -> ClarificationProposal {
        let lower = capture.text.lowercased()
        let memoryPrefixes = ["remember:", "note:", "idea:"]
        if memoryPrefixes.contains(where: lower.hasPrefix) {
            return try ClarificationProposal(
                captureID: capture.id,
                disposition: .memory,
                desiredOutcome: nil,
                nextAction: nil,
                confidence: 0.9
            )
        }

        let actionPrefixes = ["todo:", "do:"]
        if let prefix = actionPrefixes.first(where: lower.hasPrefix) {
            let start = capture.text.index(capture.text.startIndex, offsetBy: prefix.count)
            let action = String(capture.text[start...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if action.isEmpty == false {
                return try ClarificationProposal(
                    captureID: capture.id,
                    disposition: .action,
                    desiredOutcome: action,
                    nextAction: action,
                    confidence: 0.75
                )
            }
        }

        return try ClarificationProposal(
            captureID: capture.id,
            disposition: .unclear,
            desiredOutcome: nil,
            nextAction: nil,
            confidence: 1
        )
    }
}
