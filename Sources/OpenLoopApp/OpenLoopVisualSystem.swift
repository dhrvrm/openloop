import SwiftUI

enum OpenLoopVisualSystem {
    // MARK: Adaptive color language

    static let accent = Color(nsColor: .systemBlue)
    static let accentSoft = accent.opacity(0.12)
    static let accentHover = accent.opacity(0.075)
    static let recording = Color(nsColor: .systemRed)
    static let today = Color(nsColor: .systemYellow)
    static let inbox = Color(nsColor: .systemBlue)
    static let later = Color(nsColor: .systemGreen)
    static let returnColor = Color(nsColor: .systemGray)
    static let context = Color(nsColor: .systemTeal)
    static let emerging = Color(nsColor: .systemPurple)
    static let ask = Color(nsColor: .systemBlue)
    static let act = Color(nsColor: .systemOrange)

    static let canvas = Color(nsColor: .textBackgroundColor)
    static let sidebar = Color(nsColor: .windowBackgroundColor).opacity(0.96)
    static let raised = Color(nsColor: .controlBackgroundColor).opacity(0.78)
    static let selection = Color.primary.opacity(0.075)
    static let selectionInactive = Color.primary.opacity(0.045)
    static let hairline = Color.primary.opacity(0.085)
    static let separator = Color.primary.opacity(0.075)
    static let muted = Color.primary.opacity(0.52)
    static let tertiaryText = Color.primary.opacity(0.34)

    // MARK: Geometry

    static let sidebarWidth: CGFloat = 238
    static let contentMaximumWidth: CGFloat = 720
    static let inspectorIdealWidth: CGFloat = 348
    static let checkboxSize: CGFloat = 18
    static let checkboxHitSize: CGFloat = 28
    static let taskRowMinimumHeight: CGFloat = 47
    static let compactRowMinimumHeight: CGFloat = 31
    static let sidebarSelectionRadius: CGFloat = 7
    static let inputRadius: CGFloat = 9
    static let editorRadius: CGFloat = 11
    static let panelRadius: CGFloat = 11
    static let contentTopPadding: CGFloat = 43
    static let contentHorizontalPadding: CGFloat = 48

    // MARK: Type

    static let listTitle = Font.system(size: 35, weight: .bold)
    static let projectTitle = Font.system(size: 30, weight: .semibold)
    static let sectionTitle = Font.system(size: 16, weight: .semibold)
    static let rowTitle = Font.system(size: 16, weight: .regular)
    static let rowTitleEmphasized = Font.system(size: 16, weight: .medium)
    static let metadata = Font.system(size: 13, weight: .regular)
    static let sidebarLabel = Font.system(size: 15, weight: .regular)
    static let sidebarLabelSelected = Font.system(size: 15, weight: .medium)

    static func tint(for destination: WorkspaceDestination.ID) -> Color {
        switch destination {
        case .now: today
        case .inbox: inbox
        case .later: later
        case .return: returnColor
        case .context: context
        case .emerging: emerging
        case .ask: ask
        case .act: act
        }
    }

    static func icon(forSurfaceTitle title: String) -> String {
        switch title {
        case "Now": "star.fill"
        case "Inbox": "tray.fill"
        case "Later": "archivebox.fill"
        case "Return": "arrow.uturn.backward.circle.fill"
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
        case "Inbox": inbox
        case "Later": later
        case "Return": returnColor
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
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .frame(minHeight: 28)
            .background(
                configuration.isPressed ? tint.opacity(0.13) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: configuration.isPressed)
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
}
