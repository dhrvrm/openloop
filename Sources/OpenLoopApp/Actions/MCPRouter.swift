import ADHDCore
import Foundation

struct PreparedMCPAction: Equatable, Identifiable, Sendable {
    let id: UUID
    let route: CapabilityRoute
    let intent: String
    let summary: String
    let parameters: [String: String]
    let isConfirmed: Bool

    var canExecute: Bool {
        ProposedToolAction(
            route: route,
            summary: summary,
            confirmed: isConfirmed
        ).canExecute
    }

    func confirmed() -> PreparedMCPAction {
        PreparedMCPAction(
            id: id,
            route: route,
            intent: intent,
            summary: summary,
            parameters: parameters,
            isConfirmed: true
        )
    }
}

actor MCPRouter {
    private let registry: CapabilityRegistry

    init(registry: CapabilityRegistry) {
        self.registry = registry
    }

    func prepare(
        intent: String,
        parameters: [String: String],
        summary: String
    ) async throws -> PreparedMCPAction {
        guard let route = await registry.graph().routes(
            intent: intent,
            requiring: .act,
            limit: 1
        ).first else { throw CapabilityRuntimeError.noRoute }
        let required = Set(route.capability.inputSchema.keys)
        let missing = required.subtracting(parameters.keys).sorted()
        guard missing.isEmpty else {
            throw CapabilityRuntimeError.invalidParameters(missing)
        }
        return PreparedMCPAction(
            id: UUID(),
            route: route,
            intent: intent,
            summary: summary,
            parameters: parameters,
            isConfirmed: false
        )
    }
}
