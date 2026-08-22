import Foundation

struct ShortcutFeedback: Equatable, Identifiable, Sendable {
    enum Kind: Sendable {
        case capture
        case recording
        case dictation
        case search
        case warning
    }

    let id: UUID
    let kind: Kind
    let title: String
    let shortcut: String

    init(kind: Kind, title: String, shortcut: String, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
        self.title = title
        self.shortcut = shortcut
    }
}
