import SwiftUI

enum OpenLoopVisualSystem {
    // MARK: Adaptive color language

    static let accent = adaptive(light: 0x187F73, dark: 0x50C6B4)
    static let accentSoft = accent.opacity(0.10)
    static let accentHover = accent.opacity(0.075)
    static let recording = adaptive(light: 0xD84A4A, dark: 0xFF6666)

    // Category colors are punctuation, not surface fills.
    static let today = accent
    static let inbox = accent
    static let later = adaptive(light: 0x61776F, dark: 0x91AAA1)
    static let returnColor = adaptive(light: 0x7D8790, dark: 0x9CA4AD)
    static let context = accent
    static let emerging = adaptive(light: 0x4D766F, dark: 0x82AEA6)
    static let ask = accent
    static let act = accent

    static let canvas = adaptive(light: 0xFAF9F6, dark: 0x242523)
    static let sidebar = adaptive(light: 0xF1F0EC, dark: 0x1D1F1D)
    static let raised = adaptive(light: 0xFFFFFF, dark: 0x2D2E31)
    static let selection = adaptive(light: 0xE1E4DF, dark: 0x393D39)
    static let selectionInactive = adaptive(light: 0xECEDE9, dark: 0x303330)
    static let pressed = adaptive(light: 0xD9DDD7, dark: 0x444944)
    static let hairline = adaptive(light: 0xDEDED8, dark: 0x454945)
    static let separator = adaptive(light: 0xE6E5E0, dark: 0x393D39)
    static let muted = adaptive(light: 0x706F6A, dark: 0xAAA9A4)
    static let tertiaryText = adaptive(light: 0x96958F, dark: 0x7E817D)
    static let focusRing = accent.opacity(0.34)

    // MARK: Geometry

    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 20
    static let space5: CGFloat = 32

    static let sidebarWidth: CGFloat = 252
    static let contentMaximumWidth: CGFloat = 760
    static let inspectorIdealWidth: CGFloat = 320
    static let checkboxSize: CGFloat = 18
    static let checkboxHitSize: CGFloat = 28
    static let taskRowMinimumHeight: CGFloat = 48
    static let compactRowMinimumHeight: CGFloat = 34
    static let sidebarSelectionRadius: CGFloat = 8
    static let inputRadius: CGFloat = 8
    static let editorRadius: CGFloat = 10
    static let panelRadius: CGFloat = 10
    static let contentTopPadding: CGFloat = 56
    static let contentBottomPadding: CGFloat = 64
    static let contentHorizontalPadding: CGFloat = 40
    static let inspectorTopPadding: CGFloat = 32
    static let inspectorBottomPadding: CGFloat = 40

    // MARK: Type

    static let listTitle = Font.system(size: 34, weight: .semibold)
    static let projectTitle = Font.system(size: 30, weight: .semibold)
    static let sectionTitle = Font.system(size: 15, weight: .semibold)
    static let rowTitle = Font.system(size: 16, weight: .regular)
    static let rowTitleEmphasized = Font.system(size: 16, weight: .medium)
    static let metadata = Font.system(size: 13, weight: .regular)
    static let sidebarLabel = Font.system(size: 14.5, weight: .regular)
    static let sidebarLabelSelected = Font.system(size: 14.5, weight: .medium)

    private static func adaptive(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return nsColor(isDark ? dark : light)
        })
    }

    private static func nsColor(_ hex: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    static func tint(for destination: WorkspaceDestination.ID) -> Color {
        switch destination {
        case .now: today
        case .upcoming: today
        case .someday: later
        case .inbox: inbox
        case .later: later
        case .return: returnColor
        case .transcripts: accent
        case .context: context
        case .emerging: emerging
        case .ask: ask
        case .act: act
        }
    }

    static func icon(forSurfaceTitle title: String) -> String {
        switch title {
        case "Now": "star.fill"
        case "Upcoming": "calendar"
        case "Someday": "archivebox.fill"
        case "Inbox": "tray.fill"
        case "Later": "archivebox.fill"
        case "Return": "arrow.uturn.backward.circle.fill"
        case "Transcripts": "waveform.and.mic"
        case "Context": "point.3.connected.trianglepath.dotted"
        case "Emerging": "sparkles"
        case "Ask your context": "text.magnifyingglass"
        case "Act": "bolt.fill"
        default: "circle.fill"
        }
    }

    static func tint(forSurfaceTitle title: String) -> Color {
        switch title {
        case "Now": today
        case "Upcoming": today
        case "Someday": later
        case "Inbox": inbox
        case "Later": later
        case "Return": returnColor
        case "Transcripts": accent
        case "Context": context
        case "Emerging": emerging
        case "Ask your context": ask
        case "Act": act
        default: accent
        }
    }
}

struct OpenLoopCheckbox: View {
    let isCompleted: Bool
    var tint: Color = OpenLoopVisualSystem.accent
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isCompleted ? tint : (isHovered ? tint.opacity(0.08) : .clear))
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(
                        isCompleted || isHovered ? tint : Color.secondary.opacity(0.43),
                        lineWidth: isCompleted ? 1.2 : 1.15
                    )
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: OpenLoopVisualSystem.checkboxSize, height: OpenLoopVisualSystem.checkboxSize)
            .frame(
                width: OpenLoopVisualSystem.checkboxHitSize,
                height: OpenLoopVisualSystem.checkboxHitSize
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovered }
        }
        .accessibilityLabel(isCompleted ? "Completed" : "Mark complete")
    }
}

struct OpenLoopSectionHeading: View {
    let title: String
    var tint: Color = OpenLoopVisualSystem.accent
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: detail == nil ? 0 : 3) {
            HStack(spacing: 10) {
                Text(title)
                    .font(OpenLoopVisualSystem.sectionTitle)
                    .foregroundStyle(tint)
                Rectangle()
                    .fill(OpenLoopVisualSystem.separator)
                    .frame(height: 1)
            }
            if let detail {
                Text(detail)
                    .font(OpenLoopVisualSystem.metadata)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 24)
            }
        }
        .padding(.top, 8)
    }
}

struct OpenLoopAccessoryButtonStyle: ButtonStyle {
    var tint: Color = OpenLoopVisualSystem.accent

    func makeBody(configuration: Configuration) -> some View {
        OpenLoopAccessoryButtonBody(configuration: configuration, tint: tint)
    }
}

private struct OpenLoopAccessoryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isEnabled ? tint : OpenLoopVisualSystem.tertiaryText)
            .padding(.horizontal, 9)
            .frame(minHeight: 28)
            .background(
                backgroundColor,
                in: RoundedRectangle(
                    cornerRadius: OpenLoopVisualSystem.sidebarSelectionRadius,
                    style: .continuous
                )
            )
            .opacity(isEnabled ? 1 : 0.72)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.86),
                value: configuration.isPressed
            )
            .onHover { isHovered = $0 }
    }

    private var backgroundColor: Color {
        if configuration.isPressed { return OpenLoopVisualSystem.pressed }
        if isHovered && isEnabled { return tint.opacity(0.09) }
        return .clear
    }
}

struct OpenLoopNavigationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct OpenLoopInteractiveRowModifier: ViewModifier {
    let isSelected: Bool
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .background(
                isSelected
                    ? OpenLoopVisualSystem.selection
                    : (isHovered ? OpenLoopVisualSystem.selectionInactive : .clear),
                in: RoundedRectangle(
                    cornerRadius: OpenLoopVisualSystem.sidebarSelectionRadius,
                    style: .continuous
                )
            )
            .onHover { hovered in
                withAnimation(.easeOut(duration: 0.12)) { isHovered = hovered }
            }
    }
}

private struct OpenLoopPanelModifier: ViewModifier {
    let emphasized: Bool

    func body(content: Content) -> some View {
        content
            .background(
                emphasized ? OpenLoopVisualSystem.accentSoft : OpenLoopVisualSystem.raised,
                in: RoundedRectangle(
                    cornerRadius: OpenLoopVisualSystem.panelRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: OpenLoopVisualSystem.panelRadius,
                    style: .continuous
                )
                .stroke(
                    emphasized
                        ? OpenLoopVisualSystem.accent.opacity(0.16)
                        : OpenLoopVisualSystem.hairline,
                    lineWidth: 0.75
                )
            }
    }
}

extension View {
    func openLoopPanel(emphasized: Bool = false) -> some View {
        modifier(OpenLoopPanelModifier(emphasized: emphasized))
    }

    func openLoopInteractiveRow(isSelected: Bool = false) -> some View {
        modifier(OpenLoopInteractiveRowModifier(isSelected: isSelected))
    }
}
