import ADHDCore
import AppKit
import Foundation

@MainActor
final class ApplicationContextObserver: NSObject {
    typealias IdentityDecoder = @MainActor (Notification) -> FrontmostApplicationIdentity?

    private let notificationCenter: NotificationCenter
    private let notificationName: Notification.Name
    private let ownBundleIdentifier: String?
    private let identityDecoder: IdentityDecoder
    private let handler: @MainActor (ApplicationContext) -> Void
    private var isStarted = false

    init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        notificationName: Notification.Name = NSWorkspace.didActivateApplicationNotification,
        ownBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        identityDecoder: @escaping IdentityDecoder = ApplicationContextObserver.workspaceIdentity,
        handler: @escaping @MainActor (ApplicationContext) -> Void
    ) {
        self.notificationCenter = notificationCenter
        self.notificationName = notificationName
        self.ownBundleIdentifier = ownBundleIdentifier?.lowercased()
        self.identityDecoder = identityDecoder
        self.handler = handler
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        notificationCenter.addObserver(
            self,
            selector: #selector(receive(_:)),
            name: notificationName,
            object: nil
        )
    }

    func stop() {
        guard isStarted else { return }
        notificationCenter.removeObserver(self, name: notificationName, object: nil)
        isStarted = false
    }

    @objc private func receive(_ notification: Notification) {
        guard let identity = identityDecoder(notification),
              identity.bundleIdentifier?.lowercased() != ownBundleIdentifier,
              let bundleIdentifier = identity.bundleIdentifier,
              let applicationName = identity.applicationName,
              let application = try? ApplicationContext(
                  bundleIdentifier: bundleIdentifier,
                  applicationName: applicationName
              ) else { return }
        handler(application)
    }

    private static func workspaceIdentity(
        _ notification: Notification
    ) -> FrontmostApplicationIdentity? {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return nil }
        return FrontmostApplicationIdentity(
            bundleIdentifier: application.bundleIdentifier,
            applicationName: application.localizedName
        )
    }

    deinit {
        notificationCenter.removeObserver(self)
    }
}
