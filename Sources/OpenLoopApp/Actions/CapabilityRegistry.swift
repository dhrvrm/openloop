import ADHDCore
import Foundation

actor CapabilityRegistry {
    private let repository: any ThoughtRepository
    private var discovered: [String: ToolCapability] = [:]

    init(repository: any ThoughtRepository) {
        self.repository = repository
    }

    /// Replaces the live discovery snapshot. Tool-declared permissions are
    /// ignored; a new capability always begins at Observe.
    func discover(_ capabilities: [ToolCapability]) async throws -> [ToolCapability] {
        let grants = Dictionary(uniqueKeysWithValues: try await repository.capabilityGrants().map {
            ($0.capabilityID, $0.permission)
        })
        discovered = Dictionary(uniqueKeysWithValues: capabilities.map { capability in
            let permission = grants[capability.id] ?? .observe
            return (capability.id, capability.granting(permission))
        })
        return values()
    }

    func grant(
        _ permission: CapabilityPermission,
        capabilityID: String,
        at date: Date = .now
    ) async throws -> ToolCapability {
        guard let capability = discovered[capabilityID] else {
            throw CapabilityRuntimeError.capabilityUnavailable(capabilityID)
        }
        let updated = capability.granting(permission)
        discovered[capabilityID] = updated
        var grants = try await repository.capabilityGrants().filter {
            $0.capabilityID != capabilityID
        }
        grants.append(CapabilityGrant(
            capabilityID: capabilityID,
            permission: permission,
            updatedAt: date
        ))
        try await repository.save(capabilityGrants: grants)
        return updated
    }

    func graph() -> CapabilityGraph {
        CapabilityGraph(capabilities: values())
    }

    func values() -> [ToolCapability] {
        discovered.values.sorted { $0.id < $1.id }
    }
}

enum CapabilityRuntimeError: Error, Equatable {
    case capabilityUnavailable(String)
    case noRoute
    case confirmationRequired
    case invalidParameters([String])
}
