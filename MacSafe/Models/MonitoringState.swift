import Foundation

// MARK: - Monitoring State

enum MonitoringState: Equatable {
    case idle           // Normal operation, sensors off
    case monitoring     // Active environmental monitoring
    case alerting       // Alert triggered, waiting for acknowledgment
    case suspended      // Manually disabled by user
}

// MARK: - State Machine Events

enum StateMachineEvent {
    // Activation triggers
    case screenLocked
    case screenSaverStarted
    case idleThresholdReached
    case manualActivation

    // Deactivation triggers
    case screenUnlocked
    case userActivityDetected
    case manualDeactivation

    // In-monitoring sensor events
    case motionDetected(score: Float)
    case faceDetected(boundingBox: CGRect)
    case loudSoundDetected(dBFS: Float)
    case lidOpened

    // Alert lifecycle
    case alertAcknowledged
    case alertTimeout
}

// MARK: - Alert Type

enum AlertType: String, Codable {
    case motion = "motion"
    case face = "face"
    case audio = "audio"
    case lidOpened = "lid_opened"

    var localizedTitle: String {
        switch self {
        case .motion:    return "Motion Detected"
        case .face:      return "Face Detected"
        case .audio:     return "Sound Detected"
        case .lidOpened: return "Lid Opened"
        }
    }

    var systemImageName: String {
        switch self {
        case .motion:    return "figure.walk"
        case .face:      return "face.smiling"
        case .audio:     return "waveform"
        case .lidOpened: return "laptopcomputer.and.arrow.down"
        }
    }
}

// MARK: - Screen Event

enum ScreenEvent {
    case locked
    case unlocked
    case screensaverStarted
    case screensaverStopped
    case displaySleep
    case displayWake
    case lidOpened      // Lid physically opened while MacBook was closed
}
