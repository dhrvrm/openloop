import ADHDCore
import Foundation
import Testing
@testable import OpenLoopApp

@Test func stdioRuntimeInitializesDiscoversAndCallsALocalTool() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let serverURL = directory.appendingPathComponent("fixture_mcp.py")
    try fixtureServer.write(to: serverURL, atomically: true, encoding: .utf8)
    let configurationURL = directory.appendingPathComponent("servers.json")
    let configuration = """
    {
      "servers": [{
        "id": "fixture",
        "command": "python3",
        "arguments": ["\(serverURL.path)"],
        "environment": {},
        "workingDirectory": null,
        "protocolMode": "legacy",
        "enabled": true
      }]
    }
    """
    try configuration.write(to: configurationURL, atomically: true, encoding: .utf8)

    let runtime = MCPRuntime(configurationURL: configurationURL)
    let capabilities = await runtime.discoverCapabilities()
    let capability = try #require(capabilities.first)

    #expect(capabilities.count == 1)
    #expect(capability.id == "fixture.create_note")
    #expect(capability.grantedPermission == .observe)
    #expect(capability.risk == .reversibleWrite)
    #expect(capability.inputSchema.keys.sorted() == ["title"])

    let result = try await runtime.invoke(
        server: "fixture",
        tool: "create_note",
        parameters: ["title": "Release plan"]
    )
    #expect(result == "Created Release plan")
    await runtime.close()
}

private let fixtureServer = #"""
import json
import sys

for line in sys.stdin:
    request = json.loads(line)
    method = request.get("method")
    request_id = request.get("id")
    if method == "notifications/initialized":
        continue
    if method == "initialize":
        result = {
            "protocolVersion": "2025-11-25",
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "fixture", "version": "1.0"}
        }
    elif method == "tools/list":
        result = {
            "tools": [{
                "name": "create_note",
                "title": "Create note",
                "description": "Create a reversible local note",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "title": {"type": "string", "description": "Note title"},
                        "body": {"type": "string", "description": "Optional body"}
                    },
                    "required": ["title"]
                }
            }]
        }
    elif method == "tools/call":
        title = request["params"]["arguments"]["title"]
        result = {
            "content": [{"type": "text", "text": "Created " + title}],
            "isError": False
        }
    else:
        print(json.dumps({
            "jsonrpc": "2.0",
            "id": request_id,
            "error": {"code": -32601, "message": "Method not found"}
        }), flush=True)
        continue
    print(json.dumps({"jsonrpc": "2.0", "id": request_id, "result": result}), flush=True)
"""#
