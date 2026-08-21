import ADHDCore
import AppKit
import ApplicationServices
import Foundation

enum TextOutputRoute: String, Equatable, Sendable {
    case accessibility
    case clipboardPaste
    case simulatedKeyboard
    case unavailable
}

struct TextOutputResult: Equatable, Sendable {
    let route: TextOutputRoute
    let inserted: Bool
}

@MainActor protocol AccessibilityTextInserting: AnyObject {
    func insert(_ text: String) -> Bool
}

@MainActor protocol ClipboardTextPasting: AnyObject {
    func paste(_ text: String) -> Bool
}

@MainActor protocol KeyboardTextTyping: AnyObject {
    func type(_ text: String) -> Bool
    func perform(_ command: VoiceCommand) -> Bool
}

extension KeyboardTextTyping {
    @MainActor func perform(_ command: VoiceCommand) -> Bool { false }
}

@MainActor
final class TextOutputAdapter {
    private let accessibility: any AccessibilityTextInserting
    private let clipboard: any ClipboardTextPasting
    private let keyboard: any KeyboardTextTyping

    init(
        accessibility: any AccessibilityTextInserting,
        clipboard: any ClipboardTextPasting,
        keyboard: any KeyboardTextTyping
    ) {
        self.accessibility = accessibility
        self.clipboard = clipboard
        self.keyboard = keyboard
    }

    func insert(_ text: String) -> TextOutputResult {
        guard !text.isEmpty else { return TextOutputResult(route: .unavailable, inserted: false) }
        if accessibility.insert(text) {
            return TextOutputResult(route: .accessibility, inserted: true)
        }
        if clipboard.paste(text) {
            return TextOutputResult(route: .clipboardPaste, inserted: true)
        }
        if keyboard.type(text) {
            return TextOutputResult(route: .simulatedKeyboard, inserted: true)
        }
        return TextOutputResult(route: .unavailable, inserted: false)
    }

    func perform(_ command: VoiceCommand) -> TextOutputResult {
        switch command {
        case .newLine:
            return insert("\n")
        case .newParagraph:
            return insert("\n\n")
        case .undo, .deleteSelection, .submit:
            let performed = keyboard.perform(command)
            return TextOutputResult(
                route: performed ? .simulatedKeyboard : .unavailable,
                inserted: performed
            )
        }
    }
}

@MainActor
final class SystemAccessibilityTextInserter: AccessibilityTextInserting {
    func insert(_ text: String) -> Bool {
        guard AXIsProcessTrusted(),
              let application = NSWorkspace.shared.frontmostApplication else { return false }
        let app = AXUIElementCreateApplication(application.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app,
            kAXFocusedUIElementAttribute as CFString,
            &value
        ) == .success,
        let focusedValue = value,
        CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { return false }
        let focused = focusedValue as! AXUIElement
        return AXUIElementSetAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        ) == .success
    }
}

@MainActor
final class RestoringClipboardPaster: ClipboardTextPasting {
    private let pasteboard: NSPasteboard
    private let postPaste: @MainActor @Sendable () -> Bool

    init(
        pasteboard: NSPasteboard = .general,
        postPaste: @escaping @MainActor @Sendable () -> Bool = SystemKeyboardTyper.postPasteShortcut
    ) {
        self.pasteboard = pasteboard
        self.postPaste = postPaste
    }

    func paste(_ text: String) -> Bool {
        let prior = pasteboard.pasteboardItems?.compactMap { item -> [String: Data]? in
            var values: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { values[type.rawValue] = data }
            }
            return values
        } ?? []
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string), postPaste() else {
            restore(prior)
            return false
        }
        restore(prior)
        return true
    }

    private func restore(_ values: [[String: Data]]) {
        pasteboard.clearContents()
        let items = values.map { stored -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in stored { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}

@MainActor
final class SystemKeyboardTyper: KeyboardTextTyping {
    func type(_ text: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        for unit in text.utf16 {
            var character = UniChar(unit)
            guard let down = CGEvent(
                keyboardEventSource: nil,
                virtualKey: 0,
                keyDown: true
            ), let up = CGEvent(
                keyboardEventSource: nil,
                virtualKey: 0,
                keyDown: false
            ) else { return false }
            down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &character)
            up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &character)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
        return true
    }

    func perform(_ command: VoiceCommand) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        switch command {
        case .undo:
            return Self.postKey(keyCode: 6, flags: .maskCommand)
        case .deleteSelection:
            return Self.postKey(keyCode: 51)
        case .submit:
            return Self.postKey(keyCode: 36)
        case .newLine:
            return Self.postKey(keyCode: 36)
        case .newParagraph:
            return Self.postKey(keyCode: 36) && Self.postKey(keyCode: 36)
        }
    }

    static func postPasteShortcut() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        return postKey(keyCode: 9, flags: .maskCommand)
    }

    private static func postKey(keyCode: CGKeyCode, flags: CGEventFlags = []) -> Bool {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else { return false }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
