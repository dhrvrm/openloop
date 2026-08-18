import SwiftUI

enum OpenLoopVisualSystem {
    static let accent = Color(red: 0.10, green: 0.52, blue: 0.49)
    static let accentSoft = accent.opacity(0.11)
    static let canvas = Color(nsColor: .underPageBackgroundColor)
    static let sidebar = Color(nsColor: .windowBackgroundColor).opacity(0.92)
    static let raised = Color(nsColor: .controlBackgroundColor).opacity(0.76)
    static let hairline = Color.primary.opacity(0.075)
    static let muted = Color.primary.opacity(0.54)
    static let panelRadius: CGFloat = 14
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
