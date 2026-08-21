import Testing
@testable import ADHDCore

private let capabilityFixture = CapabilityGraph(capabilities: [
    ToolCapability(
        id: "github.inspect",
        server: "GitHub",
        tool: "inspect_repository",
        intents: ["inspect", "repository", "code", "github"],
        grantedPermission: .observe,
        risk: .readOnly
    ),
    ToolCapability(
        id: "github.create-pr",
        server: "GitHub",
        tool: "create_pull_request",
        intents: ["create", "pull", "request", "pr", "github"],
        grantedPermission: .act,
        risk: .reversibleWrite
    ),
    ToolCapability(
        id: "github.delete-repository",
        server: "GitHub",
        tool: "delete_repository",
        intents: ["delete", "repository", "github"],
        grantedPermission: .suggest,
        risk: .destructive
    ),
    ToolCapability(
        id: "vercel.deployments",
        server: "Vercel",
        tool: "list_deployments",
        intents: ["deployment", "deploy", "vercel", "status"],
        grantedPermission: .observe,
        risk: .readOnly
    ),
])

@Test func capabilityGraphDiscoversToolsFromIntentWithoutMCPVocabulary() {
    let routes = capabilityFixture.routes(
        intent: "What happened to the deployment status?",
        requiring: .observe
    )

    #expect(routes.map(\.capability.id) == ["vercel.deployments"])
    #expect(!routes[0].requiresConfirmation)
}

@Test func capabilityGraphNeverRoutesAboveGrantedPermission() {
    #expect(capabilityFixture.routes(
        intent: "delete the github repository",
        requiring: .act
    ).isEmpty)
    #expect(capabilityFixture.routes(
        intent: "delete the github repository",
        requiring: .suggest
    ).map(\.capability.id).contains("github.delete-repository"))
}

@Test func writableActionsRequireConfirmationBeforeExecution() throws {
    let route = try #require(capabilityFixture.routes(
        intent: "create a github pull request",
        requiring: .act
    ).first)

    #expect(route.requiresConfirmation)
    #expect(!ProposedToolAction(route: route, summary: "Create PR").canExecute)
    #expect(ProposedToolAction(
        route: route,
        summary: "Create PR",
        confirmed: true
    ).canExecute)
}
