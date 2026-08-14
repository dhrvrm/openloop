import AppKit

@MainActor
final class QuickCaptureController: NSObject, NSTextFieldDelegate {
    private let panel: NSPanel
    private let field = NSTextField()
    private let status = NSTextField(labelWithString: "")
    private let model: AppModel
    private(set) var latency = CaptureLatency()
    private var visibilityTask: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 116),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        configure()
    }

    func show(startedAt: ContinuousClock.Instant = .now) {
        status.stringValue = ""
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        visibilityTask?.cancel()
        let windowNumber = CGWindowID(panel.windowNumber)
        visibilityTask = Task { [weak self] in
            for _ in 0..<1_000 {
                guard Task.isCancelled == false else { return }
                if Self.isOnscreen(windowNumber) {
                    let elapsed = startedAt.duration(to: .now)
                    let milliseconds = Double(elapsed.components.seconds) * 1_000
                        + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
                    self?.latency.record(milliseconds: milliseconds)
                    return
                }
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
    }

    func hide() {
        visibilityTask?.cancel()
        panel.orderOut(nil)
    }

    func waitForSample(after previousCount: Int) async -> Bool {
        for _ in 0..<1_000 {
            if latency.samples.count > previousCount { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            submit()
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            hide()
            return true
        }
        return false
    }

    private func configure() {
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        guard let content = panel.contentView else { return }
        field.placeholderString = "What do you need to get out of your head?"
        field.font = .systemFont(ofSize: 20)
        field.focusRingType = .none
        field.delegate = self
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 12)
        for view in [field, status] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            field.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            field.topAnchor.constraint(equalTo: content.topAnchor, constant: 30),
            field.heightAnchor.constraint(equalToConstant: 36),
            status.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            status.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 8),
        ])
    }

    private func submit() {
        Task {
            _ = await submitCurrentText()
        }
    }

    @discardableResult
    func submitCurrentText() async -> Bool {
        if await model.submitCapture(field.stringValue) {
            field.stringValue = ""
            hide()
            return true
        }
        status.stringValue = model.captureError ?? "Could not save."
        return false
    }

    var textForTesting: String {
        get { field.stringValue }
        set { field.stringValue = newValue }
    }

    func waitUntilHidden() async -> Bool {
        let windowNumber = CGWindowID(panel.windowNumber)
        for _ in 0..<1_000 {
            if Self.isOnscreen(windowNumber) == false { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }

    private static func isOnscreen(_ windowNumber: CGWindowID) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow],
            windowNumber
        ) as? [[String: Any]],
        let window = windows.first else { return false }
        return window[kCGWindowIsOnscreen as String] as? Bool == true
    }
}
