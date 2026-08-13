import Foundation

public enum CaptureSource: String, Codable, Sendable {
    case typed
    case voice
    case ambientDraft
}

public enum CaptureError: Error, Equatable {
    case emptyText
}

public struct RawCapture: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let source: CaptureSource
    public let text: String

    public init(
        id: UUID = UUID(),
        createdAt: Date,
        source: CaptureSource = .typed,
        text: String
    ) throws {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { throw CaptureError.emptyText }

        self.id = id
        self.createdAt = createdAt
        self.source = source
        self.text = normalized
    }
}
