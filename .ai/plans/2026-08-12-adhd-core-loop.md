# ADHD Thought Loop Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local, independently testable Swift core that durably captures an unstructured thought and moves it through clarification, activation, interruption, resumption, and closure.

**Architecture:** A dependency-free domain package owns immutable values and state transitions. Repository and clarification protocols connect replaceable adapters; the first adapters are deterministic rules and an atomic JSON file store. A command-line executable proves the full behavior before AppKit, voice, models, or a DMG are introduced.

**Tech Stack:** Swift 6.2, Swift Package Manager, Foundation, Swift Testing, JSON persistence.

---

## Scope

This plan implements Increment 0 only. It contains no account, network, cloud,
organization, speech recognition, model download, telemetry, website, or billing.
It deliberately has no GUI. Increment 1 will connect the passing core to the
menu-bar interface and package it as a `.dmg`.

## File map

- `Package.swift`: declares the core, local-store, and CLI targets.
- `Sources/ADHDCore/Capture.swift`: raw externalized thought values.
- `Sources/ADHDCore/Clarification.swift`: disposition and proposed-action values.
- `Sources/ADHDCore/Intention.swift`: intention state and transitions.
- `Sources/ADHDCore/Ports.swift`: persistence and clarification interfaces.
- `Sources/ADHDCore/ThoughtLoop.swift`: one orchestration boundary for the loop.
- `Sources/LocalStore/JSONFileThoughtRepository.swift`: atomic local persistence.
- `Sources/RuleClarifier/RuleClarificationProvider.swift`: deterministic first provider.
- `Sources/ThoughtLoopCLI/main.swift`: manual end-to-end harness.
- `Tests/ADHDCoreTests/IntentionTests.swift`: state-transition tests.
- `Tests/ADHDCoreTests/ThoughtLoopTests.swift`: orchestration tests with fakes.
- `Tests/LocalStoreTests/JSONFileThoughtRepositoryTests.swift`: restart and corruption tests.
- `Tests/RuleClarifierTests/RuleClarificationProviderTests.swift`: deterministic classification tests.

### Task 1: Create the package and capture values

**Files:**
- Create: `Package.swift`
- Create: `Sources/ADHDCore/Capture.swift`
- Test: `Tests/ADHDCoreTests/CaptureTests.swift`

- [ ] **Step 1: Create the package manifest**

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenLoopADHD",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ADHDCore", targets: ["ADHDCore"]),
    ],
    targets: [
        .target(name: "ADHDCore"),
        .testTarget(name: "ADHDCoreTests", dependencies: ["ADHDCore"]),
    ]
)
```

- [ ] **Step 2: Write the failing capture tests**

```swift
import Foundation
import Testing
@testable import ADHDCore

@Test func captureTrimsOuterWhitespaceWithoutChangingMeaning() throws {
    let capture = try RawCapture(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        createdAt: Date(timeIntervalSince1970: 10),
        text: "  Send Riya the revised flow  "
    )

    #expect(capture.text == "Send Riya the revised flow")
}

@Test func emptyCaptureIsRejected() {
    #expect(throws: CaptureError.emptyText) {
        try RawCapture(createdAt: .now, text: " \n ")
    }
}
```

- [ ] **Step 3: Run the test to verify failure**

```bash
swift test --filter CaptureTests
```

Expected: compilation fails because `RawCapture` and `CaptureError` do not exist.

- [ ] **Step 4: Implement capture values**

```swift
import Foundation

public enum CaptureSource: String, Codable, Sendable {
    case typed
    case voice
    case ambientDraft
}

public enum CaptureError: Error, Equatable {
    case emptyText
}

public struct RawCapture: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let source: CaptureSource
    public let text: String

    public init(
        id: UUID = UUID(),
        createdAt: Date,
        source: CaptureSource = .typed,
        text: String
    ) throws {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { throw CaptureError.emptyText }
        self.id = id
        self.createdAt = createdAt
        self.source = source
        self.text = normalized
    }
}
```

- [ ] **Step 5: Run tests and commit**

```bash
swift test --filter CaptureTests
git add Package.swift Sources/ADHDCore/Capture.swift Tests/ADHDCoreTests/CaptureTests.swift
git commit -m "feat: add raw thought capture values"
```

Expected: two tests pass before the commit.

### Task 2: Define clarification without requiring AI

**Files:**
- Create: `Sources/ADHDCore/Clarification.swift`
- Test: `Tests/ADHDCoreTests/ClarificationTests.swift`

- [ ] **Step 1: Write failing validation tests**

```swift
import Foundation
import Testing
@testable import ADHDCore

@Test func actionRequiresOutcomeAndNextAction() throws {
    #expect(throws: ClarificationError.actionRequiresNextStep) {
        try ClarificationProposal(
            captureID: UUID(),
            disposition: .action,
            desiredOutcome: "Send the flow",
            nextAction: nil,
            confidence: 0.8
        )
    }
}

@Test func memoryDoesNotInventAnAction() throws {
    let proposal = try ClarificationProposal(
        captureID: UUID(),
        disposition: .memory,
        desiredOutcome: nil,
        nextAction: nil,
        confidence: 1
    )
    #expect(proposal.nextAction == nil)
}

@Test func confidenceMustBeNormalized() {
    #expect(throws: ClarificationError.invalidConfidence) {
        try ClarificationProposal(
            captureID: UUID(),
            disposition: .unclear,
            desiredOutcome: nil,
            nextAction: nil,
            confidence: 1.1
        )
    }
}
```

- [ ] **Step 2: Verify failure**

```bash
swift test --filter ClarificationTests
```

Expected: compilation fails because clarification values do not exist.

- [ ] **Step 3: Implement clarification values**

```swift
import Foundation

public enum Disposition: String, Codable, Sendable {
    case action
    case memory
    case later
    case release
    case unclear
}

public enum ClarificationError: Error, Equatable {
    case actionRequiresNextStep
    case invalidConfidence
}

public struct ClarificationProposal: Codable, Equatable, Sendable {
    public let captureID: UUID
    public let disposition: Disposition
    public let desiredOutcome: String?
    public let nextAction: String?
    public let confidence: Double

    public init(
        captureID: UUID,
        disposition: Disposition,
        desiredOutcome: String?,
        nextAction: String?,
        confidence: Double
    ) throws {
        guard (0...1).contains(confidence) else {
            throw ClarificationError.invalidConfidence
        }
        if disposition == .action {
            let outcomeMissing = desiredOutcome?.isEmpty ?? true
            let actionMissing = nextAction?.isEmpty ?? true
            guard outcomeMissing == false, actionMissing == false else {
                throw ClarificationError.actionRequiresNextStep
            }
        }
        self.captureID = captureID
        self.disposition = disposition
        self.desiredOutcome = desiredOutcome
        self.nextAction = nextAction
        self.confidence = confidence
    }
}
```

- [ ] **Step 4: Run tests and commit**

```bash
swift test --filter ClarificationTests
git add Sources/ADHDCore/Clarification.swift Tests/ADHDCoreTests/ClarificationTests.swift
git commit -m "feat: define safe thought clarification"
```

Expected: three tests pass.

### Task 3: Implement the intention lifecycle

**Files:**
- Create: `Sources/ADHDCore/Intention.swift`
- Test: `Tests/ADHDCoreTests/IntentionTests.swift`

- [ ] **Step 1: Write the lifecycle test**

```swift
import Foundation
import Testing
@testable import ADHDCore

@Test func intentionSupportsInterruptionAndReturn() throws {
    var intention = Intention(
        id: UUID(),
        sourceCaptureID: UUID(),
        desiredOutcome: "Send Riya the revised flow",
        nextAction: "Open the latest Figma link",
        state: .open,
        createdAt: Date(timeIntervalSince1970: 10),
        returnPacket: nil
    )

    try intention.transition(to: .active)
    let packet = try ReturnPacket(
        capturedAt: Date(timeIntervalSince1970: 20),
        justCompleted: "Found the correct design file",
        nextAction: "Copy its link into the message",
        blocker: nil,
        references: ["https://figma.example/design"]
    )
    try intention.interrupt(with: packet)
    #expect(intention.state == .interrupted)
    #expect(intention.returnPacket == packet)

    try intention.resume()
    #expect(intention.state == .active)
    #expect(intention.nextAction == "Copy its link into the message")

    try intention.transition(to: .closed)
    #expect(intention.state == .closed)
}

@Test func closedIntentionCannotRestart() throws {
    var intention = Intention(
        id: UUID(),
        sourceCaptureID: UUID(),
        desiredOutcome: "Archive the note",
        nextAction: "Move the note to Archive",
        state: .open,
        createdAt: .now,
        returnPacket: nil
    )
    try intention.transition(to: .closed)
    #expect(throws: IntentionError.invalidTransition(from: .closed, to: .active)) {
        try intention.transition(to: .active)
    }
}
```

- [ ] **Step 2: Verify failure**

```bash
swift test --filter IntentionTests
```

Expected: compilation fails because intention lifecycle values do not exist.

- [ ] **Step 3: Implement the lifecycle**

```swift
import Foundation

public enum IntentionState: String, Codable, Hashable, Sendable {
    case open
    case active
    case interrupted
    case closed
    case released
}

public enum IntentionError: Error, Equatable {
    case invalidTransition(from: IntentionState, to: IntentionState)
    case interruptionRequiresActiveState
    case resumeRequiresInterruptedState
    case emptyNextAction
}

public struct ReturnPacket: Codable, Equatable, Sendable {
    public let capturedAt: Date
    public let justCompleted: String?
    public let nextAction: String
    public let blocker: String?
    public let references: [String]

    public init(
        capturedAt: Date,
        justCompleted: String?,
        nextAction: String,
        blocker: String?,
        references: [String]
    ) throws {
        guard nextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw IntentionError.emptyNextAction
        }
        self.capturedAt = capturedAt
        self.justCompleted = justCompleted
        self.nextAction = nextAction
        self.blocker = blocker
        self.references = references
    }
}

public struct Intention: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sourceCaptureID: UUID
    public let desiredOutcome: String
    public private(set) var nextAction: String
    public private(set) var state: IntentionState
    public let createdAt: Date
    public private(set) var returnPacket: ReturnPacket?

    public init(
        id: UUID,
        sourceCaptureID: UUID,
        desiredOutcome: String,
        nextAction: String,
        state: IntentionState,
        createdAt: Date,
        returnPacket: ReturnPacket?
    ) {
        self.id = id
        self.sourceCaptureID = sourceCaptureID
        self.desiredOutcome = desiredOutcome
        self.nextAction = nextAction
        self.state = state
        self.createdAt = createdAt
        self.returnPacket = returnPacket
    }

    public mutating func transition(to target: IntentionState) throws {
        let allowed: Set<IntentionState>
        switch state {
        case .open: allowed = [.active, .closed, .released]
        case .active: allowed = [.interrupted, .closed, .released]
        case .interrupted: allowed = [.active, .closed, .released]
        case .closed, .released: allowed = []
        }
        guard allowed.contains(target) else {
            throw IntentionError.invalidTransition(from: state, to: target)
        }
        state = target
    }

    public mutating func interrupt(with packet: ReturnPacket) throws {
        guard state == .active else {
            throw IntentionError.interruptionRequiresActiveState
        }
        returnPacket = packet
        state = .interrupted
    }

    public mutating func resume() throws {
        guard state == .interrupted else {
            throw IntentionError.resumeRequiresInterruptedState
        }
        if let packet = returnPacket { nextAction = packet.nextAction }
        state = .active
    }
}
```

- [ ] **Step 4: Run tests and commit**

```bash
swift test --filter IntentionTests
git add Sources/ADHDCore/Intention.swift Tests/ADHDCoreTests/IntentionTests.swift
git commit -m "feat: add interruption-safe intention lifecycle"
```

Expected: two tests pass.

### Task 4: Define ports and orchestrate the thought loop

**Files:**
- Create: `Sources/ADHDCore/Ports.swift`
- Create: `Sources/ADHDCore/ThoughtLoop.swift`
- Test: `Tests/ADHDCoreTests/ThoughtLoopTests.swift`

- [ ] **Step 1: Write the end-to-end core test with fakes**

```swift
import Foundation
import Testing
@testable import ADHDCore

private actor MemoryRepository: ThoughtRepository {
    var captures: [UUID: RawCapture] = [:]
    var intentions: [UUID: Intention] = [:]

    func save(capture: RawCapture) async throws { captures[capture.id] = capture }
    func save(intention: Intention) async throws { intentions[intention.id] = intention }
    func intention(id: UUID) async throws -> Intention? { intentions[id] }
    func openIntentions() async throws -> [Intention] {
        intentions.values.filter { $0.state != .closed && $0.state != .released }
    }
}

private struct FixedClarifier: ClarificationProvider {
    func propose(for capture: RawCapture) async throws -> ClarificationProposal {
        try ClarificationProposal(
            captureID: capture.id,
            disposition: .action,
            desiredOutcome: "Reply to Riya",
            nextAction: "Open Riya's latest message",
            confidence: 1
        )
    }
}

@Test func capturePersistsBeforeItBecomesAnIntention() async throws {
    let repository = MemoryRepository()
    let loop = ThoughtLoop(repository: repository, clarifier: FixedClarifier())

    let result = try await loop.capture(text: "reply to Riya", at: .now)

    #expect(await repository.captures[result.capture.id] != nil)
    #expect(result.intention?.nextAction == "Open Riya's latest message")
    #expect(try await repository.openIntentions().count == 1)
}
```

- [ ] **Step 2: Verify failure**

```bash
swift test --filter ThoughtLoopTests
```

Expected: compilation fails because ports and `ThoughtLoop` do not exist.

- [ ] **Step 3: Implement the ports**

```swift
import Foundation

public protocol ThoughtRepository: Sendable {
    func save(capture: RawCapture) async throws
    func save(intention: Intention) async throws
    func intention(id: UUID) async throws -> Intention?
    func openIntentions() async throws -> [Intention]
}

public protocol ClarificationProvider: Sendable {
    func propose(for capture: RawCapture) async throws -> ClarificationProposal
}
```

- [ ] **Step 4: Implement the orchestrator**

```swift
import Foundation

public struct CaptureResult: Sendable {
    public let capture: RawCapture
    public let proposal: ClarificationProposal
    public let intention: Intention?
}

public struct ThoughtLoop: Sendable {
    private let repository: any ThoughtRepository
    private let clarifier: any ClarificationProvider

    public init(
        repository: any ThoughtRepository,
        clarifier: any ClarificationProvider
    ) {
        self.repository = repository
        self.clarifier = clarifier
    }

    public func capture(text: String, at date: Date) async throws -> CaptureResult {
        let capture = try RawCapture(createdAt: date, text: text)
        try await repository.save(capture: capture)
        let proposal = try await clarifier.propose(for: capture)

        let intention: Intention?
        if proposal.disposition == .action,
           let outcome = proposal.desiredOutcome,
           let nextAction = proposal.nextAction {
            let value = Intention(
                id: UUID(),
                sourceCaptureID: capture.id,
                desiredOutcome: outcome,
                nextAction: nextAction,
                state: .open,
                createdAt: date,
                returnPacket: nil
            )
            try await repository.save(intention: value)
            intention = value
        } else {
            intention = nil
        }

        return CaptureResult(capture: capture, proposal: proposal, intention: intention)
    }
}
```

- [ ] **Step 5: Run tests and commit**

```bash
swift test --filter ThoughtLoopTests
git add Sources/ADHDCore/Ports.swift Sources/ADHDCore/ThoughtLoop.swift Tests/ADHDCoreTests/ThoughtLoopTests.swift
git commit -m "feat: connect capture to the intention loop"
```

Expected: the end-to-end core test passes.

### Task 5: Add atomic local persistence

**Files:**
- Modify: `Package.swift`
- Create: `Sources/LocalStore/JSONFileThoughtRepository.swift`
- Test: `Tests/LocalStoreTests/JSONFileThoughtRepositoryTests.swift`

- [ ] **Step 1: Add the local-store targets and write the restart test**

Replace `Package.swift` with:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenLoopADHD",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ADHDCore", targets: ["ADHDCore"]),
        .library(name: "LocalStore", targets: ["LocalStore"]),
    ],
    targets: [
        .target(name: "ADHDCore"),
        .target(name: "LocalStore", dependencies: ["ADHDCore"]),
        .testTarget(name: "ADHDCoreTests", dependencies: ["ADHDCore"]),
        .testTarget(name: "LocalStoreTests", dependencies: ["ADHDCore", "LocalStore"]),
    ]
)
```

Create the test:

```swift
import ADHDCore
import Foundation
import Testing
@testable import LocalStore

@Test func savedThoughtsSurviveRepositoryRestart() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let capture = try RawCapture(createdAt: .now, text: "Email the revised flow")
    let intention = Intention(
        id: UUID(),
        sourceCaptureID: capture.id,
        desiredOutcome: "Riya receives the new flow",
        nextAction: "Open the latest Figma file",
        state: .open,
        createdAt: .now,
        returnPacket: nil
    )

    let writer = try JSONFileThoughtRepository(directory: directory)
    try await writer.save(capture: capture)
    try await writer.save(intention: intention)

    let reader = try JSONFileThoughtRepository(directory: directory)
    #expect(try await reader.intention(id: intention.id) == intention)
    #expect(try await reader.openIntentions() == [intention])
}
```

- [ ] **Step 2: Verify failure**

```bash
swift test --filter JSONFileThoughtRepositoryTests
```

Expected: compilation fails because the repository does not exist.

- [ ] **Step 3: Implement the repository**

```swift
import ADHDCore
import Foundation

private struct Snapshot: Codable {
    var captures: [UUID: RawCapture] = [:]
    var intentions: [UUID: Intention] = [:]
}

public actor JSONFileThoughtRepository: ThoughtRepository {
    private let fileURL: URL
    private var snapshot: Snapshot

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        fileURL = directory.appendingPathComponent("thought-loop.json")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            snapshot = try JSONDecoder().decode(
                Snapshot.self,
                from: Data(contentsOf: fileURL)
            )
        } else {
            snapshot = Snapshot()
        }
    }

    public func save(capture: RawCapture) async throws {
        snapshot.captures[capture.id] = capture
        try persist()
    }

    public func save(intention: Intention) async throws {
        snapshot.intentions[intention.id] = intention
        try persist()
    }

    public func intention(id: UUID) async throws -> Intention? {
        snapshot.intentions[id]
    }

    public func openIntentions() async throws -> [Intention] {
        snapshot.intentions.values
            .filter { $0.state != .closed && $0.state != .released }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
```

- [ ] **Step 4: Run tests and commit**

```bash
swift test --filter JSONFileThoughtRepositoryTests
git add Package.swift Sources/LocalStore/JSONFileThoughtRepository.swift Tests/LocalStoreTests/JSONFileThoughtRepositoryTests.swift
git commit -m "feat: persist the thought loop locally"
```

Expected: the restart test passes.

### Task 6: Add a deterministic clarification provider

**Files:**
- Modify: `Package.swift`
- Create: `Sources/RuleClarifier/RuleClarificationProvider.swift`
- Test: `Tests/RuleClarifierTests/RuleClarificationProviderTests.swift`

- [ ] **Step 1: Add the clarification targets and write behavior tests**

Replace `Package.swift` with:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenLoopADHD",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ADHDCore", targets: ["ADHDCore"]),
        .library(name: "LocalStore", targets: ["LocalStore"]),
        .library(name: "RuleClarifier", targets: ["RuleClarifier"]),
    ],
    targets: [
        .target(name: "ADHDCore"),
        .target(name: "LocalStore", dependencies: ["ADHDCore"]),
        .target(name: "RuleClarifier", dependencies: ["ADHDCore"]),
        .testTarget(name: "ADHDCoreTests", dependencies: ["ADHDCore"]),
        .testTarget(name: "LocalStoreTests", dependencies: ["ADHDCore", "LocalStore"]),
        .testTarget(name: "RuleClarifierTests", dependencies: ["ADHDCore", "RuleClarifier"]),
    ]
)
```

Create the test:

```swift
import ADHDCore
import Foundation
import Testing
@testable import RuleClarifier

@Test(arguments: ["remember", "note", "idea"])
func memoryPrefixesRemainMemories(prefix: String) async throws {
    let provider = RuleClarificationProvider()
    let capture = try RawCapture(createdAt: .now, text: "\(prefix): Riya prefers email")
    let proposal = try await provider.propose(for: capture)
    #expect(proposal.disposition == .memory)
    #expect(proposal.nextAction == nil)
}

@Test func explicitActionUsesTheTextAsAReviewableNextStep() async throws {
    let provider = RuleClarificationProvider()
    let capture = try RawCapture(createdAt: .now, text: "todo: open the Figma file")
    let proposal = try await provider.propose(for: capture)
    #expect(proposal.disposition == .action)
    #expect(proposal.nextAction == "open the Figma file")
    #expect(proposal.confidence < 1)
}

@Test func ordinaryTextRemainsUnclearInsteadOfBecomingAFakeTask() async throws {
    let provider = RuleClarificationProvider()
    let capture = try RawCapture(createdAt: .now, text: "the launch conversation felt confusing")
    let proposal = try await provider.propose(for: capture)
    #expect(proposal.disposition == .unclear)
}
```

- [ ] **Step 2: Verify failure**

```bash
swift test --filter RuleClarificationProviderTests
```

Expected: compilation fails because the provider does not exist.

- [ ] **Step 3: Implement deterministic rules**

```swift
import ADHDCore
import Foundation

public struct RuleClarificationProvider: ClarificationProvider {
    public init() {}

    public func propose(for capture: RawCapture) async throws -> ClarificationProposal {
        let lower = capture.text.lowercased()
        let memoryPrefixes = ["remember:", "note:", "idea:"]
        if memoryPrefixes.contains(where: lower.hasPrefix) {
            return try ClarificationProposal(
                captureID: capture.id,
                disposition: .memory,
                desiredOutcome: nil,
                nextAction: nil,
                confidence: 0.9
            )
        }

        let actionPrefixes = ["todo:", "do:"]
        if let prefix = actionPrefixes.first(where: lower.hasPrefix) {
            let start = capture.text.index(capture.text.startIndex, offsetBy: prefix.count)
            let action = String(capture.text[start...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return try ClarificationProposal(
                captureID: capture.id,
                disposition: .action,
                desiredOutcome: action,
                nextAction: action,
                confidence: 0.75
            )
        }

        return try ClarificationProposal(
            captureID: capture.id,
            disposition: .unclear,
            desiredOutcome: nil,
            nextAction: nil,
            confidence: 1
        )
    }
}
```

- [ ] **Step 4: Run tests and commit**

```bash
swift test --filter RuleClarificationProviderTests
git add Package.swift Sources/RuleClarifier/RuleClarificationProvider.swift Tests/RuleClarifierTests/RuleClarificationProviderTests.swift
git commit -m "feat: clarify explicit thoughts without AI"
```

Expected: all provider tests pass.

### Task 7: Add the working command-line loop

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ThoughtLoopCLI/main.swift`

- [ ] **Step 1: Add the executable target**

Replace `Package.swift` with:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenLoopADHD",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ADHDCore", targets: ["ADHDCore"]),
        .library(name: "LocalStore", targets: ["LocalStore"]),
        .library(name: "RuleClarifier", targets: ["RuleClarifier"]),
        .executable(name: "thought-loop", targets: ["ThoughtLoopCLI"]),
    ],
    targets: [
        .target(name: "ADHDCore"),
        .target(name: "LocalStore", dependencies: ["ADHDCore"]),
        .target(name: "RuleClarifier", dependencies: ["ADHDCore"]),
        .executableTarget(
            name: "ThoughtLoopCLI",
            dependencies: ["ADHDCore", "LocalStore", "RuleClarifier"]
        ),
        .testTarget(name: "ADHDCoreTests", dependencies: ["ADHDCore"]),
        .testTarget(name: "LocalStoreTests", dependencies: ["ADHDCore", "LocalStore"]),
        .testTarget(name: "RuleClarifierTests", dependencies: ["ADHDCore", "RuleClarifier"]),
    ]
)
```

- [ ] **Step 2: Implement `capture` and `list` commands**

```swift
import ADHDCore
import Foundation
import LocalStore
import RuleClarifier

@main
struct ThoughtLoopCommand {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            print("Usage: thought-loop capture <text> | list")
            return
        }

        let dataDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OpenLoopADHD", isDirectory: true)
        let repository = try JSONFileThoughtRepository(directory: dataDirectory)

        switch command {
        case "capture":
            let text = arguments.dropFirst().joined(separator: " ")
            let loop = ThoughtLoop(
                repository: repository,
                clarifier: RuleClarificationProvider()
            )
            let result = try await loop.capture(text: text, at: .now)
            print("Saved: \(result.capture.text)")
            print("Disposition: \(result.proposal.disposition.rawValue)")
            if let intention = result.intention {
                print("Next: \(intention.nextAction)")
            }
        case "list":
            let intentions = try await repository.openIntentions()
            if intentions.isEmpty {
                print("No open intentions.")
            } else {
                for intention in intentions {
                    print("\(intention.id.uuidString)\t\(intention.state.rawValue)\t\(intention.nextAction)")
                }
            }
        default:
            print("Unknown command: \(command)")
            print("Usage: thought-loop capture <text> | list")
        }
    }
}
```

- [ ] **Step 3: Run the complete loop twice**

```bash
swift run thought-loop capture "todo: open the Figma file"
swift run thought-loop list
```

Expected first output includes `Disposition: action` and `Next: open the Figma
file`. Expected second output contains one open intention with the same next
action, proving persistence across processes.

- [ ] **Step 4: Run a non-action capture**

```bash
swift run thought-loop capture "the launch conversation felt confusing"
```

Expected: `Disposition: unclear`; the capture is saved and no fabricated action
is printed.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/ThoughtLoopCLI/main.swift
git commit -m "feat: expose the local thought loop through a CLI"
```

### Task 8: Verify Increment 0

**Files:**
- Create: `Scripts/verify.sh`
- Modify: `README.md`

- [ ] **Step 1: Create the verification script**

```bash
#!/bin/zsh
set -euo pipefail

openloop_root="${0:A:h:h}"
swift test --package-path "$openloop_root"
swift build --package-path "$openloop_root" -c release
```

- [ ] **Step 2: Make it executable and run it**

```bash
chmod +x Scripts/verify.sh
Scripts/verify.sh
```

Expected: all tests pass and the release build succeeds.

- [ ] **Step 3: Add the commands to `README.md`**

Append:

````markdown
## Development verification

Run `Scripts/verify.sh` to execute all core tests and create a release build.

Try the first local behavior with:

```bash
swift run thought-loop capture "todo: open the latest design"
swift run thought-loop list
```
````

- [ ] **Step 4: Commit**

```bash
git add Scripts/verify.sh README.md
git commit -m "build: verify the ADHD thought loop core"
```

## Completion gate

Increment 0 is complete only when all tests pass, the release build succeeds, an
action capture survives a separate process launch, ordinary emotional or
ambiguous text remains safely unclassified, and no network access occurs. The
next plan connects these proven behaviors to Quick Capture, Now, and Later and
packages the app as a `.dmg`.
