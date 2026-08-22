import ADHDCore
import Foundation

enum MCPProtocolMode: String, Codable, Sendable {
    case legacy
    case modern
}

struct MCPServerConfiguration: Codable, Equatable, Sendable {
    let id: String
    let command: String
    let arguments: [String]
    let environment: [String: String]
    let workingDirectory: String?
    let protocolMode: MCPProtocolMode
    let enabled: Bool

    init(
        id: String,
        command: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        workingDirectory: String? = nil,
        protocolMode: MCPProtocolMode = .legacy,
        enabled: Bool = true
    ) {
        self.id = id
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.protocolMode = protocolMode
        self.enabled = enabled
    }
}

private struct MCPServerConfigurationFile: Codable {
    let servers: [MCPServerConfiguration]
}

enum MCPTransportError: Error, Equatable {
    case invalidConfiguration
    case processUnavailable(String)
    case connectionClosed(Int32)
    case malformedResponse
    case remoteError(Int, String)
    case toolFailed(String)
    case serverUnavailable(String)
}

actor MCPStdioConnection {
    private static let legacyProtocolVersion = "2025-11-25"
    private static let modernProtocolVersion = "2026-07-28"

    private let configuration: MCPServerConfiguration
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errorOutput: FileHandle?
    private var receiveBuffer = Data()
    private var nextRequestID = 1
    private var pending: [Int: CheckedContinuation<Data, any Error>] = [:]
    private var connected = false

    init(configuration: MCPServerConfiguration) {
        self.configuration = configuration
    }

    func connect() async throws {
        guard !connected else { return }
        try startProcess()
        if configuration.protocolMode == .legacy {
            let params = try Self.jsonData([
                "protocolVersion": Self.legacyProtocolVersion,
                "capabilities": [:],
                "clientInfo": ["name": "OpenLoop", "version": "1.0"],
            ])
            _ = try Self.decodeEmptyResponse(
                try await request(method: "initialize", parameters: params)
            )
            try sendNotification(method: "notifications/initialized", parameters: nil)
        }
        connected = true
    }

    func listTools() async throws -> [MCPToolDefinition] {
        try await connect()
        var tools: [MCPToolDefinition] = []
        var cursor: String?
        repeat {
            let parameters = try cursor.map { try Self.jsonData(["cursor": $0]) }
                ?? Self.jsonData([:])
            let response = try Self.decode(
                MCPListToolsResult.self,
                from: try await request(method: "tools/list", parameters: parameters)
            )
            tools.append(contentsOf: response.tools)
            cursor = response.nextCursor
        } while cursor != nil
        return tools
    }

    func call(tool: String, parameters: [String: String]) async throws -> String {
        try await connect()
        let payload = try Self.jsonData([
            "name": tool,
            "arguments": parameters,
        ])
        let response = try Self.decode(
            MCPCallToolResult.self,
            from: try await request(method: "tools/call", parameters: payload)
        )
        let text = response.content.compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if response.isError == true {
            throw MCPTransportError.toolFailed(text.isEmpty ? "The tool reported an error." : text)
        }
        return text.isEmpty ? "Tool completed." : text
    }

    func close() {
        pending.values.forEach {
            $0.resume(throwing: MCPTransportError.connectionClosed(process?.terminationStatus ?? -1))
        }
        pending = [:]
        output?.readabilityHandler = nil
        errorOutput?.readabilityHandler = nil
        try? input?.close()
        if process?.isRunning == true { process?.terminate() }
        process = nil
        input = nil
        output = nil
        errorOutput = nil
        connected = false
    }

    private func startProcess() throws {
        let id = configuration.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = configuration.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !command.isEmpty else { throw MCPTransportError.invalidConfiguration }

        let process = Process()
        if command.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = configuration.arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + configuration.arguments
        }
        var environment = ProcessInfo.processInfo.environment
        environment.merge(configuration.environment) { _, configured in configured }
        process.environment = environment
        if let workingDirectory = configuration.workingDirectory, !workingDirectory.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        }

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.consume(data) }
        }
        // Always drain stderr so a noisy server cannot deadlock. Secrets and
        // server diagnostics are intentionally not copied into app state.
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        process.terminationHandler = { [weak self] process in
            Task { await self?.terminated(status: process.terminationStatus) }
        }
        do {
            try process.run()
        } catch {
            throw MCPTransportError.processUnavailable(command)
        }
        self.process = process
        input = inputPipe.fileHandleForWriting
        output = outputPipe.fileHandleForReading
        errorOutput = errorPipe.fileHandleForReading
    }

    private func request(method: String, parameters: Data?) async throws -> Data {
        let id = nextRequestID
        nextRequestID += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try writeMessage(id: id, method: method, parameters: parameters)
            } catch {
                pending.removeValue(forKey: id)?.resume(throwing: error)
            }
        }
    }

    private func sendNotification(method: String, parameters: Data?) throws {
        try writeMessage(id: nil, method: method, parameters: parameters)
    }

    private func writeMessage(id: Int?, method: String, parameters: Data?) throws {
        guard let input else { throw MCPTransportError.serverUnavailable(configuration.id) }
        var object: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if let id { object["id"] = id }
        var parameterObject = try parameters.map(Self.jsonObject) as? [String: Any] ?? [:]
        if configuration.protocolMode == .modern {
            parameterObject["_meta"] = [
                "io.modelcontextprotocol/protocolVersion": Self.modernProtocolVersion,
                "io.modelcontextprotocol/clientInfo": ["name": "OpenLoop", "version": "1.0"],
                "io.modelcontextprotocol/clientCapabilities": [:],
            ]
        }
        if !parameterObject.isEmpty { object["params"] = parameterObject }
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(0x0A)
        try input.write(contentsOf: data)
    }

    private func consume(_ data: Data) {
        receiveBuffer.append(data)
        while let newline = receiveBuffer.firstIndex(of: 0x0A) {
            let line = receiveBuffer[..<newline]
            receiveBuffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let id = (object["id"] as? NSNumber)?.intValue,
                  let continuation = pending.removeValue(forKey: id) else { continue }
            continuation.resume(returning: Data(line))
        }
    }

    private func terminated(status: Int32) {
        pending.values.forEach {
            $0.resume(throwing: MCPTransportError.connectionClosed(status))
        }
        pending = [:]
        connected = false
    }

    private static func decode<Result: Decodable>(
        _ type: Result.Type,
        from data: Data
    ) throws -> Result {
        let response = try JSONDecoder().decode(MCPResponse<Result>.self, from: data)
        if let error = response.error {
            throw MCPTransportError.remoteError(error.code, error.message)
        }
        guard let result = response.result else { throw MCPTransportError.malformedResponse }
        return result
    }

    private static func decodeEmptyResponse(_ data: Data) throws -> Bool {
        let response = try JSONDecoder().decode(MCPResponse<MCPInitializeResult>.self, from: data)
        if let error = response.error {
            throw MCPTransportError.remoteError(error.code, error.message)
        }
        guard response.result != nil else { throw MCPTransportError.malformedResponse }
        return true
    }

    private static func jsonData(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func jsonObject(_ data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data)
    }
}

actor MCPRuntime: MCPToolInvoking {
    private let configurationURL: URL
    private var connections: [String: MCPStdioConnection] = [:]

    init(configurationURL: URL) {
        self.configurationURL = configurationURL
    }

    func discoverCapabilities() async -> [ToolCapability] {
        guard let configurations = try? loadConfigurations() else { return [] }
        var capabilities: [ToolCapability] = []
        for configuration in configurations where configuration.enabled {
            let connection = connections[configuration.id]
                ?? MCPStdioConnection(configuration: configuration)
            connections[configuration.id] = connection
            guard let tools = await discoverTools(using: connection) else { continue }
            capabilities.append(contentsOf: tools.map {
                Self.capability(server: configuration.id, tool: $0)
            })
        }
        return capabilities.sorted { $0.id < $1.id }
    }

    private func discoverTools(using connection: MCPStdioConnection) async
        -> [MCPToolDefinition]? {
        await withTaskGroup(of: [MCPToolDefinition]?.self) { group in
            group.addTask { try? await connection.listTools() }
            group.addTask {
                do {
                    try await Task.sleep(for: .seconds(5))
                    await connection.close()
                } catch {}
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    func invoke(
        server: String,
        tool: String,
        parameters: [String: String]
    ) async throws -> String {
        guard let connection = connections[server] else {
            throw MCPTransportError.serverUnavailable(server)
        }
        return try await connection.call(tool: tool, parameters: parameters)
    }

    func close() async {
        for connection in connections.values { await connection.close() }
        connections = [:]
    }

    private func loadConfigurations() throws -> [MCPServerConfiguration] {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else { return [] }
        let file = try JSONDecoder().decode(
            MCPServerConfigurationFile.self,
            from: Data(contentsOf: configurationURL)
        )
        var seen = Set<String>()
        return file.servers.filter {
            !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && seen.insert($0.id).inserted
        }
    }

    static func capability(server: String, tool: MCPToolDefinition) -> ToolCapability {
        let searchable = [server, tool.name, tool.title ?? "", tool.description ?? ""]
            .joined(separator: " ")
            .lowercased()
        let required = Set(tool.inputSchema?.required ?? [])
        let schema = Dictionary(uniqueKeysWithValues: (tool.inputSchema?.properties ?? [:])
            .filter { required.contains($0.key) }
            .map { key, value in
                (key, [value.type, value.description].compactMap { $0 }.joined(separator: " · "))
            })
        return ToolCapability(
            id: "\(server).\(tool.name)",
            server: server,
            tool: tool.name,
            intents: Set(searchable.split { !$0.isLetter && !$0.isNumber }.map(String.init)),
            grantedPermission: .observe,
            risk: risk(for: searchable),
            inputSchema: schema,
            isAvailable: true
        )
    }

    private static func risk(for searchable: String) -> CapabilityRisk {
        let destructive = ["delete", "remove", "destroy", "drop", "erase", "purge", "revoke"]
        if destructive.contains(where: searchable.contains) { return .destructive }
        let write = [
            "create", "update", "write", "send", "post", "merge", "execute", "run",
            "edit", "publish", "upload", "move", "close", "comment",
        ]
        return write.contains(where: searchable.contains) ? .reversibleWrite : .readOnly
    }
}

private struct MCPResponse<Result: Decodable>: Decodable {
    let result: Result?
    let error: MCPRemoteError?
}

private struct MCPRemoteError: Decodable {
    let code: Int
    let message: String
}

private struct MCPInitializeResult: Decodable {
    let protocolVersion: String?
}

struct MCPToolDefinition: Decodable, Equatable, Sendable {
    let name: String
    let title: String?
    let description: String?
    let inputSchema: MCPInputSchema?
}

struct MCPInputSchema: Decodable, Equatable, Sendable {
    let properties: [String: MCPInputProperty]?
    let required: [String]?
}

struct MCPInputProperty: Decodable, Equatable, Sendable {
    let type: String?
    let description: String?
}

private struct MCPListToolsResult: Decodable {
    let tools: [MCPToolDefinition]
    let nextCursor: String?
}

private struct MCPCallToolResult: Decodable {
    struct Content: Decodable {
        let type: String
        let text: String?
    }

    let content: [Content]
    let isError: Bool?
}
