import Foundation

public enum CapabilityPermission: Int, Codable, Comparable, Sendable {
    case observe = 0
    case suggest = 1
    case act = 2

    public static func < (lhs: CapabilityPermission, rhs: CapabilityPermission) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum CapabilityRisk: String, Codable, Sendable {
    case readOnly, reversibleWrite, destructive
}

public struct ToolCapability: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let server: String
    public let tool: String
    public let intents: Set<String>
    public let grantedPermission: CapabilityPermission
    public let risk: CapabilityRisk
    public let inputSchema: [String: String]
    public let isAvailable: Bool

    public init(
        id: String,
        server: String,
        tool: String,
        intents: Set<String>,
        grantedPermission: CapabilityPermission,
        risk: CapabilityRisk,
        inputSchema: [String: String] = [:],
        isAvailable: Bool = true
    ) {
        self.id = id
        self.server = server
        self.tool = tool
        self.intents = Set(intents.map { $0.lowercased() })
        self.grantedPermission = grantedPermission
        self.risk = risk
        self.inputSchema = inputSchema
        self.isAvailable = isAvailable
    }

    public func granting(_ permission: CapabilityPermission) -> ToolCapability {
        ToolCapability(
            id: id,
            server: server,
            tool: tool,
            intents: intents,
            grantedPermission: permission,
            risk: risk,
            inputSchema: inputSchema,
            isAvailable: isAvailable
        )
    }
}

public struct CapabilityGrant: Codable, Equatable, Identifiable, Sendable {
    public var id: String { capabilityID }
    public let capabilityID: String
    public let permission: CapabilityPermission
    public let updatedAt: Date

    public init(
        capabilityID: String,
        permission: CapabilityPermission,
        updatedAt: Date = .now
    ) {
        self.capabilityID = capabilityID
        self.permission = permission
        self.updatedAt = updatedAt
    }
}

public enum ToolActionStatus: String, Codable, Equatable, Sendable {
    case proposed, confirmed, executing, succeeded, failed, cancelled
}

public struct ToolActionAuditRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let actionID: UUID
    public let capabilityID: String
    public let intent: String
    public let parameters: [String: String]
    public let status: ToolActionStatus
    public let message: String?
    public let occurredAt: Date

    public init(
        id: UUID = UUID(),
        actionID: UUID,
        capabilityID: String,
        intent: String,
        parameters: [String: String],
        status: ToolActionStatus,
        message: String? = nil,
        occurredAt: Date = .now
    ) {
        self.id = id
        self.actionID = actionID
        self.capabilityID = capabilityID
        self.intent = intent
        self.parameters = parameters
        self.status = status
        self.message = message
        self.occurredAt = occurredAt
    }
}

public struct CapabilityRoute: Equatable, Sendable {
    public let capability: ToolCapability
    public let score: Int
    public let requiresConfirmation: Bool
}

public struct CapabilityGraph: Codable, Equatable, Sendable {
    public let capabilities: [ToolCapability]

    public init(capabilities: [ToolCapability]) {
        self.capabilities = capabilities.sorted { $0.id < $1.id }
    }

    public func routes(
        intent: String,
        requiring permission: CapabilityPermission,
        limit: Int = 5
    ) -> [CapabilityRoute] {
        let terms = Self.terms(intent)
        return capabilities.compactMap { capability -> CapabilityRoute? in
            guard capability.isAvailable else { return nil }
            guard capability.grantedPermission >= permission else { return nil }
            let score = terms.intersection(capability.intents).count
            // One generic token (for example only "github") is not enough to
            // select a tool; require an intent + object/action signal.
            guard score >= 2 else { return nil }
            return CapabilityRoute(
                capability: capability,
                score: score,
                requiresConfirmation: capability.risk != .readOnly
            )
        }.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.capability.id < $1.capability.id
        }.prefix(max(0, limit)).map { $0 }
    }

    private static func terms(_ value: String) -> Set<String> {
        Set(value.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }
}

public struct ProposedToolAction: Equatable, Sendable {
    public let route: CapabilityRoute
    public let summary: String
    public let confirmed: Bool

    public init(route: CapabilityRoute, summary: String, confirmed: Bool = false) {
        self.route = route
        self.summary = summary
        self.confirmed = confirmed
    }

    public var canExecute: Bool {
        route.capability.grantedPermission >= (
            route.capability.risk == .readOnly ? .observe : .act
        )
            && (!route.requiresConfirmation || confirmed)
    }
}
