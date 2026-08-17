import ADHDCore
import Foundation
import Testing
@testable import OpenLoopApp

private actor MemoryCompilerProbe: WorkingMemoryCompiling {
    enum Failure: Error { case unavailable }
    private(set) var calls = 0
    var fail = false
    let records: [MemoryRecord]

    init(records: [MemoryRecord]) {
        self.records = records
    }

    func compile() async throws -> [MemoryRecord] {
        calls += 1
        if fail { throw Failure.unavailable }
        return records
    }

    func setFailure(_ value: Bool) { fail = value }
}

@MainActor
@Test func appModelRefreshesWorkingMemoryOnlyWhenExplicitlyRequested() async throws {
    let record = appMemoryRecord()
    let compiler = MemoryCompilerProbe(records: [record])
    let model = memoryTestModel(compiler: compiler)

    #expect(model.memoryRecords.isEmpty)
    #expect(await compiler.calls == 0)

    await model.refreshMemory()

    #expect(model.memoryRecords == [record])
    #expect(model.memoryError == nil)
    #expect(model.isCompilingMemory == false)
    #expect(await compiler.calls == 1)
}

@MainActor
@Test func appModelKeepsPriorMemoryAndContainsCompilationFailure() async throws {
    let record = appMemoryRecord()
    let compiler = MemoryCompilerProbe(records: [record])
    let model = memoryTestModel(compiler: compiler)
    await model.refreshMemory()
    await compiler.setFailure(true)

    await model.refreshMemory()

    #expect(model.memoryRecords == [record])
    #expect(model.memoryError == "Working memory could not refresh. Existing evidence is unchanged.")
    #expect(model.captureError == nil)
    #expect(model.commandError == nil)
    #expect(model.recallError == nil)
}

@MainActor
private func memoryTestModel(compiler: any WorkingMemoryCompiling) -> AppModel {
    let repository = MemoryAppRepository()
    return AppModel(
        loop: ThoughtLoop(repository: repository, clarifier: MemoryUnusedClarifier()),
        readModels: ThoughtReadModels(repository: repository),
        workingMemory: compiler
    )
}

private func appMemoryRecord() -> MemoryRecord {
    let id = UUID(uuidString: "70000000-0000-0000-0000-000000000001")!
    let date = Date(timeIntervalSince1970: 70)
    return MemoryRecord(
        id: id,
        kind: .decision,
        statement: "Keep the launch deliberately small",
        confidence: 1,
        evidence: [MemoryEvidence(
            evidenceID: RecallEvidenceID(kind: .capture, id: id),
            excerpt: "decision: Keep the launch deliberately small",
            occurredAt: date
        )],
        createdAt: date,
        updatedAt: date
    )
}

private actor MemoryAppRepository: ThoughtRepository {
    func save(capture: RawCapture) async throws {}
    func save(proposal: ClarificationProposal) async throws {}
    func save(intention: Intention) async throws {}
    func captures(disposition: Disposition) async throws -> [RawCapture] { [] }
    func intention(id: UUID) async throws -> Intention? { nil }
    func openIntentions() async throws -> [Intention] { [] }
    func proposal(captureID: UUID) async throws -> ClarificationProposal? { nil }
}

private struct MemoryUnusedClarifier: ClarificationProvider {
    func propose(for capture: RawCapture) async throws -> ClarificationProposal {
        try ClarificationProposal(
            captureID: capture.id,
            disposition: .unclear,
            desiredOutcome: nil,
            nextAction: nil,
            confidence: 1
        )
    }
}
