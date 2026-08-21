import ADHDCore
import CoreGraphics
import Foundation
import simd

enum SemanticGraphPlacement: Equatable, Sendable {
    case storedVector(providerIdentifier: String, dimensions: Int)
    case topology
}

struct SemanticGraph3DNode: Equatable, Identifiable, Sendable {
    let node: SemanticNode
    let position: SIMD3<Double>
    let placement: SemanticGraphPlacement
    var id: UUID { node.id }
}

struct SemanticGraph3DScene: Equatable, Sendable {
    let nodes: [SemanticGraph3DNode]
    let relations: [SemanticRelation]

    static let empty = SemanticGraph3DScene(nodes: [], relations: [])
}

struct SemanticGraphCamera: Equatable, Sendable {
    var yaw: Double = -0.28
    var pitch: Double = 0.18
    var zoom: Double = 1

    mutating func clamp() {
        pitch = min(1.25, max(-1.25, pitch))
        zoom = min(2.8, max(0.45, zoom))
    }
}

struct ProjectedSemanticNode: Equatable, Identifiable, Sendable {
    let id: UUID
    let point: CGPoint
    let depth: Double
    let radius: Double
}

struct SemanticGraph3DLayout: Sendable {
    private let iterations: Int

    init(iterations: Int = 36) {
        self.iterations = max(0, iterations)
    }

    func scene(
        nodes: [SemanticNode],
        relations: [SemanticRelation],
        vectors: [UUID: SemanticVector]
    ) -> SemanticGraph3DScene {
        let orderedNodes = nodes.sorted { $0.id.uuidString < $1.id.uuidString }
        guard !orderedNodes.isEmpty else { return .empty }
        let validIDs = Set(orderedNodes.map(\.id))
        let groundedRelations = relations.filter {
            validIDs.contains($0.sourceID) && validIDs.contains($0.targetID)
        }.sorted { $0.id.uuidString < $1.id.uuidString }

        var positions: [UUID: SIMD3<Double>] = [:]
        var placements: [UUID: SemanticGraphPlacement] = [:]
        for (index, node) in orderedNodes.enumerated() {
            if let vector = vectors[node.id] {
                positions[node.id] = reduce(vector.values)
                placements[node.id] = .storedVector(
                    providerIdentifier: vector.providerIdentifier,
                    dimensions: vector.values.count
                )
            } else {
                positions[node.id] = seededPosition(id: node.id, ordinal: index)
                placements[node.id] = .topology
            }
        }

        relax(
            positions: &positions,
            nodeIDs: orderedNodes.map(\.id),
            relations: groundedRelations,
            vectorBackedIDs: Set(vectors.keys)
        )
        normalize(&positions)

        return SemanticGraph3DScene(
            nodes: orderedNodes.map { node in
                SemanticGraph3DNode(
                    node: node,
                    position: positions[node.id] ?? .zero,
                    placement: placements[node.id] ?? .topology
                )
            },
            relations: groundedRelations
        )
    }

    func project(
        _ scene: SemanticGraph3DScene,
        size: CGSize,
        camera inputCamera: SemanticGraphCamera
    ) -> [ProjectedSemanticNode] {
        guard size.width > 0, size.height > 0 else { return [] }
        var camera = inputCamera
        camera.clamp()
        let scale = min(size.width, size.height) * 0.32 * camera.zoom
        return scene.nodes.map { item in
            let rotated = rotate(item.position, yaw: camera.yaw, pitch: camera.pitch)
            let perspective = 1 / max(0.55, 1.2 + rotated.z * 0.16)
            return ProjectedSemanticNode(
                id: item.id,
                point: CGPoint(
                    x: size.width / 2 + rotated.x * scale * perspective,
                    y: size.height / 2 - rotated.y * scale * perspective
                ),
                depth: rotated.z,
                radius: (7 + item.node.confidence * 5) * perspective
            )
        }.sorted {
            if $0.depth != $1.depth { return $0.depth < $1.depth }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func hitTest(
        point: CGPoint,
        projectedNodes: [ProjectedSemanticNode]
    ) -> UUID? {
        projectedNodes.reversed().first { projected in
            let dx = projected.point.x - point.x
            let dy = projected.point.y - point.y
            let hitRadius = max(14, projected.radius + 6)
            return dx * dx + dy * dy <= hitRadius * hitRadius
        }?.id
    }

    private func reduce(_ values: [Double]) -> SIMD3<Double> {
        let normalizer = sqrt(Double(max(1, values.count)))
        var result = SIMD3<Double>.zero
        for (index, value) in values.enumerated() {
            let phase = Double(index + 1)
            result.x += value * sin(phase * 0.754_877_666)
            result.y += value * cos(phase * 1.324_717_957)
            result.z += value * sin(phase * 2.414_213_562 + 0.5)
        }
        result /= normalizer
        return SIMD3(tanh(result.x), tanh(result.y), tanh(result.z))
    }

    private func seededPosition(id: UUID, ordinal: Int) -> SIMD3<Double> {
        let bytes = Array(id.uuidString.utf8)
        let seed = bytes.reduce(UInt64(14_695_981_039_346_656_037)) { value, byte in
            (value ^ UInt64(byte)) &* 1_099_511_628_211
        }
        let fractionA = Double(seed & 0xFFFF) / 65_535
        let fractionB = Double((seed >> 16) & 0xFFFF) / 65_535
        let angle = 2 * Double.pi * fractionA + Double(ordinal) * 0.13
        let z = 2 * fractionB - 1
        let radial = sqrt(max(0, 1 - z * z))
        return SIMD3(radial * cos(angle), radial * sin(angle), z) * 1.15
    }

    private func relax(
        positions: inout [UUID: SIMD3<Double>],
        nodeIDs: [UUID],
        relations: [SemanticRelation],
        vectorBackedIDs: Set<UUID>
    ) {
        guard nodeIDs.count > 1, iterations > 0 else { return }
        for iteration in 0..<iterations {
            var deltas = Dictionary(uniqueKeysWithValues: nodeIDs.map { ($0, SIMD3<Double>.zero) })
            for leftIndex in nodeIDs.indices {
                for rightIndex in nodeIDs.indices where rightIndex > leftIndex {
                    let leftID = nodeIDs[leftIndex]
                    let rightID = nodeIDs[rightIndex]
                    guard let left = positions[leftID], let right = positions[rightID] else { continue }
                    var difference = left - right
                    var distanceSquared = simd_length_squared(difference)
                    if distanceSquared < 0.000_1 {
                        difference = seededPosition(id: leftID, ordinal: rightIndex) * 0.01
                        distanceSquared = simd_length_squared(difference)
                    }
                    let direction = simd_normalize(difference)
                    let force = min(0.055, 0.018 / max(0.02, distanceSquared))
                    deltas[leftID, default: .zero] += direction * force
                    deltas[rightID, default: .zero] -= direction * force
                }
            }

            for relation in relations {
                guard let source = positions[relation.sourceID],
                      let target = positions[relation.targetID] else { continue }
                let difference = target - source
                let distance = max(0.001, simd_length(difference))
                let desired = 0.72 + (1 - relation.confidence) * 0.34
                let force = (distance - desired) * 0.055 * relation.confidence
                let pull = difference / distance * force
                deltas[relation.sourceID, default: .zero] += pull
                deltas[relation.targetID, default: .zero] -= pull
            }

            let cooling = 1 - Double(iteration) / Double(max(1, iterations)) * 0.72
            for id in nodeIDs {
                let anchor = vectorBackedIDs.contains(id) ? 0.58 : 1.0
                positions[id, default: .zero] += deltas[id, default: .zero] * cooling * anchor
                let length = simd_length(positions[id, default: .zero])
                if length > 2.4 {
                    positions[id, default: .zero] = positions[id, default: .zero] / length * 2.4
                }
            }
        }
    }

    private func normalize(_ positions: inout [UUID: SIMD3<Double>]) {
        guard !positions.isEmpty else { return }
        let centroid = positions.values.reduce(SIMD3<Double>.zero, +) / Double(positions.count)
        for id in positions.keys { positions[id, default: .zero] -= centroid }
        let maximum = positions.values.map(simd_length).max() ?? 0
        guard maximum > 0.000_1 else { return }
        let scale = 1.55 / maximum
        for id in positions.keys { positions[id, default: .zero] *= scale }
    }

    private func rotate(
        _ value: SIMD3<Double>,
        yaw: Double,
        pitch: Double
    ) -> SIMD3<Double> {
        let yawed = SIMD3(
            value.x * cos(yaw) - value.z * sin(yaw),
            value.y,
            value.x * sin(yaw) + value.z * cos(yaw)
        )
        return SIMD3(
            yawed.x,
            yawed.y * cos(pitch) - yawed.z * sin(pitch),
            yawed.y * sin(pitch) + yawed.z * cos(pitch)
        )
    }
}
