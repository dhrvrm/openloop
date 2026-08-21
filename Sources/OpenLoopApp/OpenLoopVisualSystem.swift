import SwiftUI

enum OpenLoopVisualSystem {
    static let accent = Color(red: 0.10, green: 0.52, blue: 0.49)
    static let accentSoft = accent.opacity(0.11)
    static let accentHover = accent.opacity(0.07)
    static let recording = Color(nsColor: .systemRed)
    static let canvas = Color(nsColor: .underPageBackgroundColor)
    static let sidebar = Color(nsColor: .windowBackgroundColor).opacity(0.88)
    static let raised = Color(nsColor: .controlBackgroundColor).opacity(0.76)
    static let hairline = Color.primary.opacity(0.075)
    static let separator = Color.primary.opacity(0.065)
    static let muted = Color.primary.opacity(0.54)
    static let panelRadius: CGFloat = 14
    static let sidebarWidth: CGFloat = 252
    static let contentMaximumWidth: CGFloat = 760
    static let taskRowMinimumHeight: CGFloat = 44
    static let compactRowMinimumHeight: CGFloat = 34
    static let inspectorIdealWidth: CGFloat = 350
}

private struct OpenLoopPanelModifier: ViewModifier {
    let emphasized: Bool

    func body(content: Content) -> some View {
        content
            .background(
                emphasized ? OpenLoopVisualSystem.accentSoft : OpenLoopVisualSystem.raised,
                in: RoundedRectangle(cornerRadius: OpenLoopVisualSystem.panelRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: OpenLoopVisualSystem.panelRadius, style: .continuous)
                    .stroke(
                        emphasized
                            ? OpenLoopVisualSystem.accent.opacity(0.20)
                            : OpenLoopVisualSystem.hairline,
                        lineWidth: 1
                    )
            }
    }
}

extension View {
    func openLoopPanel(emphasized: Bool = false) -> some View {
        modifier(OpenLoopPanelModifier(emphasized: emphasized))
    }
}
