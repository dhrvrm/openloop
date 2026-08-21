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

    public init(
        id: String,
        server: String,
        tool: String,
        intents: Set<String>,
        grantedPermission: CapabilityPermission,
        risk: CapabilityRisk
    ) {
        self.id = id
        self.server = server
        self.tool = tool
        self.intents = Set(intents.map { $0.lowercased() })
        self.grantedPermission = grantedPermission
        self.risk = risk
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
            guard capability.grantedPermission >= permission else { return nil }
            let score = terms.intersection(capability.intents).count
            // One generic token (for example only "github") is not enough to
            // select a tool; require an intent + object/action signal.
            guard score >= 2 else { return nil }
            return CapabilityRoute(
                capability: capability,
                score: score,
                requiresConfirmation: permission == .act
                    && capability.risk != .readOnly
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
        route.capability.grantedPermission == .act
            && (!route.requiresConfirmation || confirmed)
    }
}
