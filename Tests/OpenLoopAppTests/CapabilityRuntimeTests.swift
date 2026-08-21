import ADHDCore
import Foundation
import Testing
@testable import OpenLoopApp

private actor CapabilityRuntimeRepository: ThoughtRepository {
    private var grants: [CapabilityGrant] = []
    private var audit: [ToolActionAuditRecord] = []

    func save(capture: RawCapture) async throws {}
    func save(proposal: ClarificationProposal) async throws {}
    func save(intention: Intention) async throws {}
    func proposal(captureID: UUID) async throws -> ClarificationProposal? { nil }
    func captures(disposition: Disposition) async throws -> [RawCapture] { [] }
    func intention(id: UUID) async throws -> Intention? { nil }
    func openIntentions() async throws -> [Intention] { [] }
    func save(capabilityGrants: [CapabilityGrant]) async throws { grants = capabilityGrants }
    func capabilityGrants() async throws -> [CapabilityGrant] { grants }
    func append(toolActionAuditRecord: ToolActionAuditRecord) async throws {
        audit.append(toolActionAuditRecord)
    }
    func toolActionAuditRecords() async throws -> [ToolActionAuditRecord] { audit }
}

private actor CapabilityRuntimeInvoker: MCPToolInvoking {
    private(set) var calls: [(String, String, [String: String])] = []

    func invoke(
        server: String,
        tool: String,
        parameters: [String: String]
    ) async throws -> String {
        calls.append((server, tool, parameters))
        return "Prepared pull request #42"
    }

    func callCount() -> Int { calls.count }
}

private func createPRCapability() -> ToolCapability {
    ToolCapability(
        id: "github.create-pr",
        server: "GitHub",
        tool: "create_pull_request",
        intents: ["create", "pull", "request", "github"],
        grantedPermission: .act,
        risk: .reversibleWrite,
        inputSchema: ["title": "string"]
    )
}

@Test func discoveredCapabilitiesDefaultToObserveAndPersistExplicitActGrant() async throws {
    let repository = CapabilityRuntimeRepository()
    let registry = CapabilityRegistry(repository: repository)

    let discovered = try await registry.discover([createPRCapability()])
    #expect(discovered.map(\.grantedPermission) == [.observe])
    #expect(await registry.graph().routes(
        intent: "create github pull request",
        requiring: .act
    ).isEmpty)

    _ = try await registry.grant(.act, capabilityID: "github.create-pr")
    #expect(try await repository.capabilityGrants().map(\.permission) == [.act])

    let reopened = CapabilityRegistry(repository: repository)
    #expect(try await reopened.discover([createPRCapability()]).map(\.grantedPermission) == [.act])
}

@Test func actionRequiresConfirmationAndWritesAnAppendOnlyAuditBeforeExecution() async throws {
    let repository = CapabilityRuntimeRepository()
    let registry = CapabilityRegistry(repository: repository)
    _ = try await registry.discover([createPRCapability()])
    _ = try await registry.grant(.act, capabilityID: "github.create-pr")
    let router = MCPRouter(registry: registry)
    let invoker = CapabilityRuntimeInvoker()
    let executor = ActionExecutor(repository: repository, invoker: invoker)
    let action = try await router.prepare(
        intent: "create github pull request",
        parameters: ["title": "Ship local voice"],
        summary: "Create a pull request titled Ship local voice"
    )

    try await executor.propose(action)
    await #expect(throws: CapabilityRuntimeError.confirmationRequired) {
        try await executor.execute(action)
    }
    #expect(await invoker.callCount() == 0)

    let confirmed = try await executor.confirm(action)
    let result = try await executor.execute(confirmed)
    #expect(result == "Prepared pull request #42")
    #expect(await invoker.callCount() == 1)
    let records = try await repository.toolActionAuditRecords()
    #expect(records.map(\.status) == [.proposed, .confirmed, .executing, .succeeded])
    #expect(Set(records.map(\.actionID)) == [action.id])
}

@Test func routerRejectsMissingRequiredParametersBeforeWritingAnAudit() async throws {
    let repository = CapabilityRuntimeRepository()
    let registry = CapabilityRegistry(repository: repository)
    _ = try await registry.discover([createPRCapability()])
    _ = try await registry.grant(.act, capabilityID: "github.create-pr")
    let router = MCPRouter(registry: registry)

    await #expect(throws: CapabilityRuntimeError.invalidParameters(["title"])) {
        try await router.prepare(
            intent: "create github pull request",
            parameters: [:],
            summary: "Create a pull request"
        )
    }
    #expect(try await repository.toolActionAuditRecords().isEmpty)
}
