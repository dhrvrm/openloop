import ADHDCore
import Foundation
import Testing
@testable import OpenLoopApp

private func graphNode(
    id: UUID,
    kind: SemanticNodeKind = .concept,
    claim: String
) throws -> SemanticNode {
    try SemanticNode(
        id: id,
        kind: kind,
        claim: claim,
        confidence: 0.8,
        status: .active,
        evidence: [try SemanticEvidence(
            id: RecallEvidenceID(kind: .capture, id: id),
            excerpt: claim,
            occurredAt: Date(timeIntervalSince1970: 10)
        )]
    )
}

@Test func graph3DLayoutIsDeterministicAndFinite() throws {
    let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let first = try graphNode(id: firstID, claim: "OpenLoop")
    let second = try graphNode(id: secondID, kind: .problem, claim: "Release reliability")
    let relation = try SemanticRelation(
        sourceID: second.id,
        targetID: first.id,
        kind: .partOf,
        confidence: 0.9
    )
    let vector = try SemanticVector(
        providerIdentifier: "fixture-v1",
        values: [0.1, -0.2, 0.4, 0.7]
    )
    let layout = SemanticGraph3DLayout()

    let firstScene = layout.scene(
        nodes: [second, first],
        relations: [relation],
        vectors: [first.id: vector]
    )
    let secondScene = layout.scene(
        nodes: [first, second],
        relations: [relation],
        vectors: [first.id: vector]
    )

    #expect(firstScene == secondScene)
    #expect(firstScene.nodes.allSatisfy {
        $0.position.x.isFinite && $0.position.y.isFinite && $0.position.z.isFinite
    })
    #expect(firstScene.nodes.first(where: { $0.id == first.id })?.placement ==
        .storedVector(providerIdentifier: "fixture-v1", dimensions: 4))
    #expect(firstScene.nodes.first(where: { $0.id == second.id })?.placement == .topology)
}

@Test func graph3DProjectionSupportsBoundedCameraAndHitTesting() throws {
    let id = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
    let node = try graphNode(id: id, claim: "A visible memory")
    let layout = SemanticGraph3DLayout()
    let scene = layout.scene(nodes: [node], relations: [], vectors: [:])
    var camera = SemanticGraphCamera(yaw: 0.2, pitch: 9, zoom: 99)
    camera.clamp()

    let projection = layout.project(scene, size: CGSize(width: 600, height: 420), camera: camera)

    #expect(camera.pitch == 1.25)
    #expect(camera.zoom == 2.8)
    #expect(projection.count == 1)
    #expect(layout.hitTest(point: projection[0].point, projectedNodes: projection) == id)
    #expect(layout.hitTest(point: .zero, projectedNodes: projection) == nil)
}

@Test func emptyGraphProducesAnEmptySceneAndProjection() {
    let layout = SemanticGraph3DLayout()
    let scene = layout.scene(nodes: [], relations: [], vectors: [:])

    #expect(scene == .empty)
    #expect(layout.project(
        scene,
        size: CGSize(width: 600, height: 420),
        camera: SemanticGraphCamera()
    ).isEmpty)
}
