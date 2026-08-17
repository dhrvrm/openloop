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
    private let identifier: EventHotKeyID

    init(
        keyCode: UInt32 = UInt32(kVK_Space),
        modifiers: UInt32 = UInt32(cmdKey | shiftKey),
        id: UInt32 = 1,
        action: @escaping @MainActor @Sendable (ContinuousClock.Instant) -> Void
    ) throws {
        self.action = action
        identifier = EventHotKeyID(signature: OSType(0x4f4c4144), id: id)
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, pointer in
                guard let event, let pointer else { return OSStatus(eventNotHandledErr) }
                let instance = Unmanaged<GlobalHotKey>.fromOpaque(pointer).takeUnretainedValue()
                var received = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &received
                )
                guard status == noErr,
                      received.signature == instance.identifier.signature,
                      received.id == instance.identifier.id else {
                    return OSStatus(eventNotHandledErr)
                }
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
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
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
