import ADHDCore
import Foundation

protocol MCPToolInvoking: Sendable {
    func invoke(
        server: String,
        tool: String,
        parameters: [String: String]
    ) async throws -> String
}

actor ActionExecutor {
    private let repository: any ThoughtRepository
    private let invoker: any MCPToolInvoking

    init(repository: any ThoughtRepository, invoker: any MCPToolInvoking) {
        self.repository = repository
        self.invoker = invoker
    }

    func propose(_ action: PreparedMCPAction, at date: Date = .now) async throws {
        try await record(action, status: .proposed, message: action.summary, at: date)
    }

    func confirm(_ action: PreparedMCPAction, at date: Date = .now) async throws
        -> PreparedMCPAction {
        let confirmed = action.confirmed()
        try await record(confirmed, status: .confirmed, at: date)
        return confirmed
    }

    func execute(_ action: PreparedMCPAction, at date: Date = .now) async throws -> String {
        guard action.canExecute else { throw CapabilityRuntimeError.confirmationRequired }
        try await record(action, status: .executing, at: date)
        do {
            let result = try await invoker.invoke(
                server: action.route.capability.server,
                tool: action.route.capability.tool,
                parameters: action.parameters
            )
            try await record(action, status: .succeeded, message: result, at: .now)
            return result
        } catch {
            try? await record(
                action,
                status: .failed,
                message: String(describing: error),
                at: .now
            )
            throw error
        }
    }

    func cancel(_ action: PreparedMCPAction, at date: Date = .now) async throws {
        try await record(action, status: .cancelled, at: date)
    }

    private func record(
        _ action: PreparedMCPAction,
        status: ToolActionStatus,
        message: String? = nil,
        at date: Date
    ) async throws {
        try await repository.append(toolActionAuditRecord: ToolActionAuditRecord(
            actionID: action.id,
            capabilityID: action.route.capability.id,
            intent: action.intent,
            parameters: action.parameters,
            status: status,
            message: message,
            occurredAt: date
        ))
    }
}
