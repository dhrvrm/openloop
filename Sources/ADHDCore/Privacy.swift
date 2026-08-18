import Foundation

public enum PrivacyRetentionPolicy: String, Codable, CaseIterable, Equatable, Sendable {
    case keepForever
    case thirtyDays
    case ninetyDays

    public var age: TimeInterval? {
        switch self {
        case .keepForever: nil
        case .thirtyDays: 30 * 24 * 60 * 60
        case .ninetyDays: 90 * 24 * 60 * 60
        }
    }
}

public struct PrivacyDataSummary: Equatable, Sendable {
    public let captureCount: Int
    public let openIntentionCount: Int
    public let completedIntentionCount: Int
    public let memoryCount: Int
    public let contextEventCount: Int
    public let encryptedBytes: Int64

    public init(
        captureCount: Int,
        openIntentionCount: Int,
        completedIntentionCount: Int,
        memoryCount: Int,
        contextEventCount: Int,
        encryptedBytes: Int64
    ) {
        self.captureCount = captureCount
        self.openIntentionCount = openIntentionCount
        self.completedIntentionCount = completedIntentionCount
        self.memoryCount = memoryCount
        self.contextEventCount = contextEventCount
        self.encryptedBytes = max(0, encryptedBytes)
    }

    public static let empty = PrivacyDataSummary(
        captureCount: 0,
        openIntentionCount: 0,
        completedIntentionCount: 0,
        memoryCount: 0,
        contextEventCount: 0,
        encryptedBytes: 0
    )
}

public struct RetentionResult: Equatable, Sendable {
    public let removedCaptures: Int
    public let removedIntentions: Int

    public init(removedCaptures: Int, removedIntentions: Int) {
        self.removedCaptures = max(0, removedCaptures)
        self.removedIntentions = max(0, removedIntentions)
    }
}
