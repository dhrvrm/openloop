import ADHDCore
import Foundation
import Testing
@testable import OpenLoopApp

@MainActor
@Test func applicationObserverEmitsOnlyValidExternalActivationsAfterStart() async throws {
    let center = NotificationCenter()
    let name = Notification.Name("context-observer-test")
    var values: [ApplicationContext] = []
    let observer = ApplicationContextObserver(
        notificationCenter: center,
        notificationName: name,
        ownBundleIdentifier: "dev.openloop.adhd",
        identityDecoder: { notification in
            notification.object as? FrontmostApplicationIdentity
        },
        handler: { values.append($0) }
    )

    center.post(
        name: name,
        object: FrontmostApplicationIdentity(
            bundleIdentifier: "dev.before-start",
            applicationName: "Before"
        )
    )
    observer.start()
    center.post(
        name: name,
        object: FrontmostApplicationIdentity(
            bundleIdentifier: "dev.openloop.adhd",
            applicationName: "OpenLoop"
        )
    )
    center.post(
        name: name,
        object: FrontmostApplicationIdentity(
            bundleIdentifier: nil,
            applicationName: "Incomplete"
        )
    )
    center.post(
        name: name,
        object: FrontmostApplicationIdentity(
            bundleIdentifier: "COM.APPLE.SAFARI",
            applicationName: " Safari "
        )
    )
    #expect(values == [try ApplicationContext(
        bundleIdentifier: "com.apple.safari",
        applicationName: "Safari"
    )])
    observer.stop()
}
