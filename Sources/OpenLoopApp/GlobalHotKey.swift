import Carbon
import Foundation

enum GlobalHotKeyError: Error {
    case install(OSStatus)
    case register(OSStatus)
}

final class GlobalHotKey: @unchecked Sendable {
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private let action: @MainActor @Sendable (ContinuousClock.Instant) -> Void

    init(action: @escaping @MainActor @Sendable (ContinuousClock.Instant) -> Void) throws {
        self.action = action
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, pointer in
                guard let pointer else { return OSStatus(eventNotHandledErr) }
                let instance = Unmanaged<GlobalHotKey>.fromOpaque(pointer).takeUnretainedValue()
                let startedAt = ContinuousClock.now
                Task { @MainActor in instance.action(startedAt) }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard installStatus == noErr else { throw GlobalHotKeyError.install(installStatus) }
        let identifier = EventHotKeyID(signature: OSType(0x4f4c4144), id: 1)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(cmdKey | shiftKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard registerStatus == noErr else { throw GlobalHotKeyError.register(registerStatus) }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
