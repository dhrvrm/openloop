# Stored Memory Graph and 3D Vector Space Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the durable semantic-memory projection and visualize only stored nodes, relations, evidence, supersession, and embedding vectors in an interactive native 3D vector-space surface.

**Architecture:** Extend append-only `SemanticGraphEvent` storage with validated model-identified vectors, using the existing encrypted repository event stream. Derive deterministic 3D coordinates from stored embeddings when present and relation topology otherwise. Publish the complete graph through `AppModel` and render it with a native SwiftUI Canvas that supports orbit, zoom, selection, depth sorting, and evidence inspection.

**Tech Stack:** Swift 6.2, SwiftUI Canvas, simd, NaturalLanguage, encrypted append-only repository, Swift Testing

---

### Task 1: Persist semantic vectors in the graph event ledger

**Files:**
- Modify: `Sources/ADHDCore/SemanticGraph.swift`
- Modify: `Sources/ADHDCore/SemanticGraphLoop.swift`
- Test: `Tests/ADHDCoreTests/SemanticGraphTests.swift`
- Test: `Tests/ADHDCoreTests/SemanticGraphLoopTests.swift`

- [ ] **Step 1: Add failing vector validation and replay tests**

Cover empty, non-finite, excessive-dimension vectors, missing-node vector events, replay, replacement by a newer vector, and history inclusion.

- [ ] **Step 2: Add `SemanticVector`**

Store `providerIdentifier`, `[Double] values`, and `createdAt`. Validate 3–4096 finite dimensions.

- [ ] **Step 3: Add vector events and graph projection state**

Add `.vector(id:occurredAt:nodeID:value:)`, `SemanticGraph.vectors`, replay validation, and history inclusion. Existing node/relation/supersession events remain source-compatible.

- [ ] **Step 4: Add `SemanticGraphLoop.storeVector`**

Validate against the current graph, append through `ThoughtRepository`, and preserve append-only semantics.

- [ ] **Step 5: Compile the core target**

Run: `swift build --target ADHDCore`.

Expected: exit 0.

### Task 2: Generate and retain local vectors without delaying capture durability

**Files:**
- Modify: `Sources/OpenLoopApp/OpenLoopApp.swift`
- Modify: `Sources/OpenLoopApp/AppModel.swift`
- Test: `Tests/OpenLoopAppTests/AppModelSemanticGraphTests.swift`

- [ ] **Step 1: Share the existing local embedding provider**

Construct one `NaturalLanguageEmbeddingProvider` for Recall and semantic memory.

- [ ] **Step 2: Schedule vector enrichment after node persistence**

Capture must return after durable node persistence. Vector generation runs as best-effort local enrichment and appends a vector event only when the provider returns a valid vector.

- [ ] **Step 3: Publish full stored graph state**

Add published relations and vectors to `AppModel.refreshSemanticGraph()`. Clear them together on unavailable/error state only when no last-known-good graph exists.

- [ ] **Step 4: Compile the app target**

Run: `swift build --target OpenLoopApp`.

Expected: exit 0.

### Task 3: Build a deterministic 3D graph layout engine

**Files:**
- Create: `Sources/OpenLoopApp/SemanticGraph3DLayout.swift`
- Create: `Tests/OpenLoopAppTests/SemanticGraph3DLayoutTests.swift`

- [ ] **Step 1: Add failing deterministic-layout tests**

Cover identical input determinism, finite coordinates, embedding reduction, topology fallback, isolated-node placement, superseded-node attenuation, depth ordering, orbit projection, zoom bounds, and empty graph.

- [ ] **Step 2: Implement layout input/output types**

Use `SIMD3<Double>` world positions, stable IDs, source metadata, and projected 2D depth values.

- [ ] **Step 3: Implement vector reduction**

Center stored vectors, project deterministically into three axes derived from stable dimension hashing, normalize robustly, and blend relation constraints.

- [ ] **Step 4: Implement topology fallback**

Use deterministic seeded spherical placement followed by bounded force iterations. Relation confidence controls attraction; all nodes repel; connected components receive stable offsets.

- [ ] **Step 5: Implement camera projection**

Support yaw, pitch, bounded zoom, perspective, depth sorting, and hit-test radii.

- [ ] **Step 6: Compile the app target**

Run: `swift build --target OpenLoopApp`.

Expected: exit 0.

### Task 4: Render the native interactive memory space

**Files:**
- Create: `Sources/OpenLoopApp/SemanticGraph3DView.swift`
- Modify: `Sources/OpenLoopApp/MainWindowController.swift`

- [ ] **Step 1: Add the graph surface to Context**

Provide List and Space modes. List remains the accessible default; Space displays the stored graph.

- [ ] **Step 2: Draw depth-aware relations and nodes**

Render back-to-front, attenuate distant elements, use kind-specific original OpenLoop glyphs/colors, indicate vector-backed versus topology-backed placement, and distinguish selected neighborhoods.

- [ ] **Step 3: Add interaction**

Drag background to orbit, scroll or magnify to zoom, click nodes to select, double-click to focus, Esc to clear, arrow keys to traverse connected neighbors, and Reset View to restore camera.

- [ ] **Step 4: Add a semantic evidence inspector**

Selection shows claim, kind, status, confidence, stored-vector provider/dimensions, relations, evidence excerpts, timestamps, and supersession history.

- [ ] **Step 5: Add accessible fallback**

Expose the same graph as a relationship outline and VoiceOver actions. Reduced Motion disables continuous settling and transition displacement.

- [ ] **Step 6: Compile without launching**

Run: `swift build --target OpenLoopApp`.

Expected: exit 0.

### Task 5: Verify storage truthfulness

**Files:**
- Modify: `.ai/plans/2026-08-21-stored-memory-graph-3d.md`

- [ ] **Step 1: Verify repository round-trip paths**

Confirm JSON development storage and encrypted production storage both replay vector events through `SemanticGraph(events:)`.

- [ ] **Step 2: Verify no fabricated graph data**

Search the view layer for relation synthesis. Only `SemanticGraph3DLayout` may derive coordinates; it may not create semantic nodes or relations.

- [ ] **Step 3: Run source checks and builds**

Run `git diff --check`, `swift build --target ADHDCore`, and `swift build --target OpenLoopApp` once each. Do not launch the GUI.

