import Foundation

struct WorkspaceDestination: Equatable, Identifiable, Sendable {
    enum ID: Int, CaseIterable, Sendable {
        case now = 0
        case context = 1
        case emerging = 2
        case ask = 3
        case act = 4
        case inbox = 5
        case later = 6
        case `return` = 7
        case transcripts = 8
    }

    let id: ID
    let title: String
    let icon: String
}

struct WorkspaceSection: Equatable, Identifiable, Sendable {
    enum ID: String, Sendable {
        case focus
        case intelligence
    }

    let id: ID
    let title: String
    let destinations: [WorkspaceDestination]
}

enum WorkspaceOrientation {
    static let sections = [
        WorkspaceSection(
            id: .focus,
            title: "Focus",
            destinations: [
                WorkspaceDestination(id: .now, title: "Now", icon: "scope"),
                WorkspaceDestination(id: .inbox, title: "Inbox", icon: "tray"),
                WorkspaceDestination(id: .later, title: "Later", icon: "archivebox"),
                WorkspaceDestination(id: .return, title: "Return", icon: "arrow.uturn.backward"),
            ]
        ),
        WorkspaceSection(
            id: .intelligence,
            title: "Intelligence",
            destinations: [
                WorkspaceDestination(id: .transcripts, title: "Transcripts", icon: "waveform.and.mic"),
                WorkspaceDestination(
                    id: .context,
                    title: "Context",
                    icon: "point.3.connected.trianglepath.dotted"
                ),
                WorkspaceDestination(id: .emerging, title: "Emerging", icon: "sparkles"),
                WorkspaceDestination(id: .ask, title: "Ask", icon: "text.magnifyingglass"),
                WorkspaceDestination(id: .act, title: "Act", icon: "bolt"),
            ]
        ),
    ]

    static let destinations = sections.flatMap(\.destinations)
    static let legacyTabOrder: [WorkspaceDestination.ID] = [.now, .context, .emerging, .ask, .act]
    static let quickCaptureShortcut = "⌘⇧Space  Quick Capture"
    static let voiceCaptureShortcut = "⌃⌥Space  Dictate & insert"
    static let emptyCaptureGuidance = "Type a thought or press Command-Shift-Space from anywhere."

    static func destination(_ id: WorkspaceDestination.ID) -> WorkspaceDestination {
        destinations.first(where: { $0.id == id })
            ?? WorkspaceDestination(id: .now, title: "Now", icon: "scope")
    }

    static func destination(atLegacyTab index: Int) -> WorkspaceDestination.ID {
        legacyTabOrder.indices.contains(index) ? legacyTabOrder[index] : .now
    }
}
