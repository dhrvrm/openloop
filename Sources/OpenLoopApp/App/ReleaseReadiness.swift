import AVFoundation
import Foundation

enum CapabilityAvailability: Equatable, Sendable {
    case ready
    case askWhenUsed
    case unavailable
    case checking
}

struct CapabilitySummary: Equatable, Sendable {
    var quickCapture: CapabilityAvailability = .checking
    var microphone: CapabilityAvailability = .checking
    var speechRecognition: CapabilityAvailability = .checking

    static func current() -> CapabilitySummary {
        CapabilitySummary(
            quickCapture: .checking,
            microphone: microphoneAvailability(AVCaptureDevice.authorizationStatus(for: .audio)),
            speechRecognition: .ready
        )
    }

    private static func microphoneAvailability(
        _ status: AVAuthorizationStatus
    ) -> CapabilityAvailability {
        switch status {
        case .authorized: .ready
        case .notDetermined: .askWhenUsed
        case .denied, .restricted: .unavailable
        @unknown default: .unavailable
        }
    }

}

struct LaunchRecoveryTracker {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "OpenLoopLaunchInProgress") {
        self.defaults = defaults
        self.key = key
    }

    func beginLaunch() -> Bool {
        let previousLaunchDidNotFinish = defaults.bool(forKey: key)
        defaults.set(true, forKey: key)
        return previousLaunchDidNotFinish
    }

    func markCleanExit() {
        defaults.set(false, forKey: key)
    }
}
