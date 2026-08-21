import ADHDCore
import AppKit
import ApplicationServices
import Foundation

struct VoiceContextSnapshot: Equatable, Sendable {
    let applicationIdentifier: String?
    let applicationName: String?
    let focusedRole: String?
    let selectedText: String?
    let surroundingText: String?
    let capturedAt: Date
}

@MainActor
protocol VoiceContextReading: AnyObject {
    func read() -> VoiceContextSnapshot
}

@MainActor
final class VoiceContextEngine {
    private let reader: any VoiceContextReading
    private let isConsented: @MainActor () -> Bool
    private let maximumContextCharacters: Int
    private let excludedBundleIdentifiers: Set<String>

    init(
        reader: any VoiceContextReading,
        maximumContextCharacters: Int = 2_000,
        excludedBundleIdentifiers: Set<String> = [
            "com.apple.keychainaccess",
            "com.1password.1password",
        ],
        isConsented: @escaping @MainActor () -> Bool
    ) {
        self.reader = reader
        self.maximumContextCharacters = max(0, maximumContextCharacters)
        self.excludedBundleIdentifiers = excludedBundleIdentifiers
        self.isConsented = isConsented
    }

    func snapshot() -> VoiceContextSnapshot? {
        guard isConsented() else { return nil }
        let value = reader.read()
        if let bundle = value.applicationIdentifier?.lowercased(),
           excludedBundleIdentifiers.contains(bundle) {
            return VoiceContextSnapshot(
                applicationIdentifier: value.applicationIdentifier,
                applicationName: value.applicationName,
                focusedRole: value.focusedRole,
                selectedText: nil,
                surroundingText: nil,
                capturedAt: value.capturedAt
            )
        }
        return VoiceContextSnapshot(
            applicationIdentifier: value.applicationIdentifier,
            applicationName: value.applicationName,
            focusedRole: value.focusedRole,
            selectedText: Self.bounded(value.selectedText, to: maximumContextCharacters),
            surroundingText: Self.bounded(value.surroundingText, to: maximumContextCharacters),
            capturedAt: value.capturedAt
        )
    }

    private static func bounded(_ value: String?, to limit: Int) -> String? {
        guard limit > 0,
              let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return String(value.prefix(limit))
    }
}

@MainActor
final class AccessibilityVoiceContextReader: VoiceContextReading {
    func read() -> VoiceContextSnapshot {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return VoiceContextSnapshot(
                applicationIdentifier: nil,
                applicationName: nil,
                focusedRole: nil,
                selectedText: nil,
                surroundingText: nil,
                capturedAt: .now
            )
        }
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let focused = Self.element(kAXFocusedUIElementAttribute, from: appElement)
        return VoiceContextSnapshot(
            applicationIdentifier: application.bundleIdentifier,
            applicationName: application.localizedName,
            focusedRole: focused.flatMap { Self.value(kAXRoleAttribute, from: $0) as? String },
            selectedText: focused.flatMap {
                Self.value(kAXSelectedTextAttribute, from: $0) as? String
            },
            surroundingText: focused.flatMap { Self.value(kAXValueAttribute, from: $0) as? String },
            capturedAt: .now
        )
    }

    private static func value(_ attribute: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func element(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        guard let value = value(attribute, from: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
