import ADHDCore
import SwiftUI

struct SemanticGraph3DView: View {
    let nodes: [SemanticNode]
    let relations: [SemanticRelation]
    let vectors: [UUID: SemanticVector]

    @State private var camera = SemanticGraphCamera()
    @State private var dragOrigin: SemanticGraphCamera?
    @State private var magnificationOrigin: Double?
    @State private var selectedID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let layout = SemanticGraph3DLayout()

    var body: some View {
        let scene = layout.scene(nodes: nodes, relations: relations, vectors: vectors)
        VStack(alignment: .leading, spacing: OpenLoopVisualSystem.space3) {
            GeometryReader { geometry in
                let projected = layout.project(scene, size: geometry.size, camera: camera)
                let projectionByID = Dictionary(uniqueKeysWithValues: projected.map { ($0.id, $0) })
                ZStack {
                    OpenLoopVisualSystem.raised.opacity(0.48)
                    Canvas { context, _ in
                        drawRelations(
                            scene: scene,
                            projections: projectionByID,
                            context: &context
                        )
                        drawNodes(
                            scene: scene,
                            projected: projected,
                            context: &context
                        )
                    }

                    ForEach(projected) { projectedNode in
                        if let semanticNode = scene.nodes.first(where: { $0.id == projectedNode.id }) {
                            Button {
                                selectedID = projectedNode.id
                            } label: {
                                Color.clear
                                    .frame(
                                        width: max(28, projectedNode.radius * 2 + 12),
                                        height: max(28, projectedNode.radius * 2 + 12)
                                    )
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .position(projectedNode.point)
                            .accessibilityLabel(semanticNode.node.claim)
                            .accessibilityValue(accessibilityValue(for: semanticNode))
                            .accessibilityHint("Select this memory node")
                        }
                    }

                    if scene.nodes.isEmpty {
                        ContentUnavailableView(
                            "No connected memory yet",
                            systemImage: "point.3.connected.trianglepath.dotted",
                            description: Text("Captured evidence will form this space as relationships are stored.")
                        )
                    }

                    VStack {
                        HStack {
                            graphLegend(scene)
                            Spacer()
                            Button("Reset view", systemImage: "viewfinder") {
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                                    camera = SemanticGraphCamera()
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                        Spacer()
                        HStack {
                            Text("Drag to orbit · pinch to zoom · select a node for evidence")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                    .padding(OpenLoopVisualSystem.space3)
                    .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: OpenLoopVisualSystem.editorRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: OpenLoopVisualSystem.editorRadius, style: .continuous)
                        .stroke(OpenLoopVisualSystem.hairline, lineWidth: 0.65)
                }
                .contentShape(Rectangle())
                .gesture(orbitGesture)
                .simultaneousGesture(zoomGesture)
                .onExitCommand { selectedID = nil }
            }
            .frame(minHeight: 380)

            if let selected = scene.nodes.first(where: { $0.id == selectedID }) {
                selectedNodeDetail(selected, scene: scene)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: selectedID)
        .onChange(of: nodes.map(\.id)) { _, identifiers in
            if let selectedID, !identifiers.contains(selectedID) { self.selectedID = nil }
        }
    }

    private var orbitGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let origin = dragOrigin ?? camera
                if dragOrigin == nil { dragOrigin = camera }
                camera.yaw = origin.yaw + value.translation.width / 220
                camera.pitch = origin.pitch - value.translation.height / 220
                camera.clamp()
            }
            .onEnded { _ in dragOrigin = nil }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let origin = magnificationOrigin ?? camera.zoom
                if magnificationOrigin == nil { magnificationOrigin = camera.zoom }
                camera.zoom = origin * value
                camera.clamp()
            }
            .onEnded { _ in magnificationOrigin = nil }
    }

    private func drawRelations(
        scene: SemanticGraph3DScene,
        projections: [UUID: ProjectedSemanticNode],
        context: inout GraphicsContext
    ) {
        let selectedNeighbors = neighborIDs(in: scene)
        for relation in scene.relations {
            guard let source = projections[relation.sourceID],
                  let target = projections[relation.targetID] else { continue }
            let touchesSelection = selectedID == nil
                || relation.sourceID == selectedID
                || relation.targetID == selectedID
            let belongsToNeighborhood = selectedID == nil
                || selectedNeighbors.contains(relation.sourceID)
                || selectedNeighbors.contains(relation.targetID)
            var path = Path()
            path.move(to: source.point)
            path.addLine(to: target.point)
            let relationColor = selectedID == nil
                ? OpenLoopVisualSystem.muted.opacity(belongsToNeighborhood ? 0.24 : 0.10)
                : OpenLoopVisualSystem.accent.opacity(touchesSelection ? 0.58 : 0.10)
            context.stroke(
                path,
                with: .color(relationColor),
                lineWidth: touchesSelection && selectedID != nil
                    ? 1.35
                    : 0.65 + relation.confidence * 0.35
            )
        }
    }

    private func drawNodes(
        scene: SemanticGraph3DScene,
        projected: [ProjectedSemanticNode],
        context: inout GraphicsContext
    ) {
        let nodesByID = Dictionary(uniqueKeysWithValues: scene.nodes.map { ($0.id, $0) })
        let selectedNeighbors = neighborIDs(in: scene)
        for projection in projected {
            guard let item = nodesByID[projection.id] else { continue }
            let isSelected = selectedID == projection.id
            let isNeighbor = selectedID == nil || selectedNeighbors.contains(projection.id)
            let depthOpacity = min(1, max(0.38, 0.76 + projection.depth * 0.12))
            let opacity = (isNeighbor || isSelected ? depthOpacity : 0.2)
            let radius = projection.radius + (isSelected ? 3 : 0)
            let rect = CGRect(
                x: projection.point.x - radius,
                y: projection.point.y - radius,
                width: radius * 2,
                height: radius * 2
            )

            if isSelected {
                context.fill(
                    Path(ellipseIn: rect.insetBy(dx: -5, dy: -5)),
                    with: .color(OpenLoopVisualSystem.accent.opacity(0.16))
                )
            }
            context.fill(
                Path(ellipseIn: rect),
                with: .color(nodeColor(item.node).opacity(opacity))
            )
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(Color.primary.opacity(isSelected ? 0.52 : 0.16)),
                lineWidth: isSelected ? 1.5 : 0.7
            )

            if isSelected || (scene.nodes.count <= 14 && projection.depth > -0.45) {
                let label = Text(shortLabel(item.node.claim))
                    .font(.caption.weight(isSelected ? .semibold : .medium))
                    .foregroundColor(.primary.opacity(isNeighbor ? 0.9 : 0.32))
                context.draw(
                    label,
                    at: CGPoint(x: projection.point.x, y: projection.point.y + radius + 7),
                    anchor: .top
                )
            }
        }
    }

    private func graphLegend(_ scene: SemanticGraph3DScene) -> some View {
        let vectorCount = scene.nodes.filter {
            if case .storedVector = $0.placement { return true }
            return false
        }.count
        return HStack(spacing: 6) {
            Circle()
                .fill(OpenLoopVisualSystem.accent)
                .frame(width: 7, height: 7)
            Text("\(scene.nodes.count) nodes · \(scene.relations.count) connections · \(vectorCount) vectors")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func selectedNodeDetail(
        _ selected: SemanticGraph3DNode,
        scene: SemanticGraph3DScene
    ) -> some View {
        let related = scene.relations.filter {
            $0.sourceID == selected.id || $0.targetID == selected.id
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(selected.node.kind.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OpenLoopVisualSystem.accent)
                Text(selected.node.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((selected.node.confidence * 100).rounded()))% confidence")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Close", systemImage: "xmark") { selectedID = nil }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            Text(selected.node.claim)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
            Text(placementDescription(selected.placement))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            if !related.isEmpty {
                Text("\(related.count) stored relationship\(related.count == 1 ? "" : "s")")
                    .font(.callout)
                ForEach(Array(related.prefix(4))) { relation in
                    let relatedID = relation.sourceID == selected.id
                        ? relation.targetID
                        : relation.sourceID
                    if let relatedNode = scene.nodes.first(where: { $0.id == relatedID }) {
                        HStack(spacing: 7) {
                            Text(relation.kind.rawValue)
                                .font(.caption.monospaced())
                                .foregroundStyle(OpenLoopVisualSystem.accent)
                            Text(relatedNode.node.claim)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text("\(Int((relation.confidence * 100).rounded()))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            ForEach(selected.node.evidence.prefix(2), id: \.id) { evidence in
                Label(evidence.excerpt, systemImage: "quote.opening")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 8)
    }

    private func neighborIDs(in scene: SemanticGraph3DScene) -> Set<UUID> {
        guard let selectedID else { return Set(scene.nodes.map(\.id)) }
        var result: Set<UUID> = [selectedID]
        for relation in scene.relations {
            if relation.sourceID == selectedID { result.insert(relation.targetID) }
            if relation.targetID == selectedID { result.insert(relation.sourceID) }
        }
        return result
    }

    private func placementDescription(_ placement: SemanticGraphPlacement) -> String {
        switch placement {
        case .storedVector(let provider, let dimensions):
            "Stored vector · \(dimensions) dimensions · \(provider)"
        case .topology:
            "Relation layout · no stored vector yet"
        }
    }

    private func accessibilityValue(for item: SemanticGraph3DNode) -> String {
        "\(item.node.kind.rawValue), \(item.node.status.rawValue), \(placementDescription(item.placement))"
    }

    private func shortLabel(_ value: String) -> String {
        let words = value.split(separator: " ")
        return words.prefix(5).joined(separator: " ")
    }

    private func nodeColor(_ node: SemanticNode) -> Color {
        if node.status == .superseded { return .secondary }
        if node.status == .speculative { return .orange }
        switch node.kind {
        case .problem, .question: return .orange
        case .decision: return Color(nsColor: .systemBlue)
        case .person: return Color(nsColor: .systemIndigo)
        default: return OpenLoopVisualSystem.accent
        }
    }
}
