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
        case upcoming = 9
        case someday = 10
    }

    let id: ID
    let title: String
    let icon: String
}

struct WorkspaceSection: Equatable, Identifiable, Sendable {
    enum ID: String, Sendable {
        case primary
        case organize
        case memory
    }

    let id: ID
    let title: String
    let destinations: [WorkspaceDestination]
}

enum WorkspaceOrientation {
    static let primarySection = WorkspaceSection(
        id: .primary,
        title: "",
        destinations: [
            WorkspaceDestination(id: .now, title: "Home", icon: "house"),
            WorkspaceDestination(id: .transcripts, title: "Voice notes", icon: "waveform"),
            WorkspaceDestination(id: .act, title: "Tasks", icon: "checkmark.circle"),
            WorkspaceDestination(id: .ask, title: "Ask OpenLoop", icon: "magnifyingglass"),
        ]
    )

    static let advancedSections = [
        WorkspaceSection(
            id: .organize,
            title: "Organize",
            destinations: [
                WorkspaceDestination(id: .upcoming, title: "Scheduled", icon: "calendar"),
                WorkspaceDestination(id: .someday, title: "Ideas", icon: "lightbulb"),
                WorkspaceDestination(id: .inbox, title: "Needs review", icon: "tray"),
                WorkspaceDestination(id: .later, title: "Saved for later", icon: "archivebox"),
                WorkspaceDestination(id: .return, title: "Pick up again", icon: "arrow.uturn.backward"),
            ]
        ),
        WorkspaceSection(
            id: .memory,
            title: "Memory",
            destinations: [
                WorkspaceDestination(
                    id: .context,
                    title: "Connections",
                    icon: "point.3.connected.trianglepath.dotted"
                ),
                WorkspaceDestination(id: .emerging, title: "Patterns", icon: "sparkles"),
            ]
        ),
    ]

    static let sections = [primarySection] + advancedSections
    static let destinations = sections.flatMap(\.destinations)
    static let legacyTabOrder: [WorkspaceDestination.ID] = [.now, .context, .emerging, .ask, .act]
    static let quickCaptureShortcut = "⌘⇧Space  Write a note"
    static let voiceCaptureShortcut = "⌃⌥Space  Type by voice"
    static let meetingRecordShortcut = "⌃⌥R  Voice note"
    static let emptyCaptureGuidance = "Write a note below, or press Command-Shift-Space from anywhere."

    static func visibleSections(advanced: Bool) -> [WorkspaceSection] {
        advanced ? sections : [primarySection]
    }

    static func destination(_ id: WorkspaceDestination.ID) -> WorkspaceDestination {
        destinations.first(where: { $0.id == id })
            ?? WorkspaceDestination(id: .now, title: "Home", icon: "house")
    }

    static func destination(atLegacyTab index: Int) -> WorkspaceDestination.ID {
        legacyTabOrder.indices.contains(index) ? legacyTabOrder[index] : .now
    }
}
