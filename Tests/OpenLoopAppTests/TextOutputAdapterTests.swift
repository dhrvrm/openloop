import Foundation
import Testing
@testable import OpenLoopApp

@MainActor
private final class OutputProbe: AccessibilityTextInserting, ClipboardTextPasting,
    KeyboardTextTyping {
    var accessibility = false
    var clipboard = false
    var keyboard = false
    private(set) var calls: [String] = []

    func insert(_ text: String) -> Bool {
        calls.append("accessibility")
        return accessibility
    }
    func paste(_ text: String) -> Bool {
        calls.append("clipboard")
        return clipboard
    }
    func type(_ text: String) -> Bool {
        calls.append("keyboard")
        return keyboard
    }
    func resetCalls() { calls = [] }
}

@MainActor
@Test func outputAdapterUsesAccessibilityBeforeFallbacks() {
    let probe = OutputProbe()
    probe.accessibility = true
    probe.clipboard = true
    probe.keyboard = true
    let adapter = TextOutputAdapter(accessibility: probe, clipboard: probe, keyboard: probe)

    #expect(adapter.insert("नमस्ते").route == .accessibility)
    #expect(probe.calls == ["accessibility"])
}

@MainActor
@Test func outputAdapterFallsBackInDeclaredOrderAndReportsFailure() {
    let probe = OutputProbe()
    probe.clipboard = true
    let adapter = TextOutputAdapter(accessibility: probe, clipboard: probe, keyboard: probe)

    #expect(adapter.insert("text").route == .clipboardPaste)
    #expect(probe.calls == ["accessibility", "clipboard"])
    probe.resetCalls()
    probe.clipboard = false
    #expect(adapter.insert("text").route == .unavailable)
    #expect(probe.calls == ["accessibility", "clipboard", "keyboard"])
}

@MainActor
private final class ContextReaderProbe: VoiceContextReading {
    let value: VoiceContextSnapshot
    init(_ value: VoiceContextSnapshot) { self.value = value }
    func read() -> VoiceContextSnapshot { value }
}

@MainActor
@Test func contextEngineRequiresConsentAndBoundsTransientText() {
    let reader = ContextReaderProbe(VoiceContextSnapshot(
        applicationIdentifier: "com.apple.TextEdit",
        applicationName: "TextEdit",
        focusedRole: "AXTextArea",
        selectedText: "selected secret",
        surroundingText: "1234567890",
        capturedAt: Date(timeIntervalSince1970: 1)
    ))
    let denied = VoiceContextEngine(reader: reader, isConsented: { false })
    let allowed = VoiceContextEngine(
        reader: reader,
        maximumContextCharacters: 5,
        isConsented: { true }
    )

    #expect(denied.snapshot() == nil)
    #expect(allowed.snapshot()?.selectedText == "selec")
    #expect(allowed.snapshot()?.surroundingText == "12345")
}

@MainActor
@Test func contextEngineNeverReadsPasswordManagerText() {
    let reader = ContextReaderProbe(VoiceContextSnapshot(
        applicationIdentifier: "com.1password.1password",
        applicationName: "1Password",
        focusedRole: "AXTextField",
        selectedText: "password",
        surroundingText: "private value",
        capturedAt: .now
    ))
    let engine = VoiceContextEngine(reader: reader, isConsented: { true })

    let value = engine.snapshot()
    #expect(value?.applicationName == "1Password")
    #expect(value?.selectedText == nil)
    #expect(value?.surroundingText == nil)
}
