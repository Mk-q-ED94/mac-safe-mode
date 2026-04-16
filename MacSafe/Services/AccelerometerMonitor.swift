import Foundation
import Combine

// MARK: - Accelerometer Event

struct AccelerometerEvent {
    enum Kind {
        /// Sudden jerk: magnitude deviates significantly from 1g (device picked up/shaken)
        case jerk(magnitude: Double)
        /// Tilt: gravity vector rotated beyond threshold (device repositioned/tilted away)
        case tilt(angleDegrees: Double)
    }
    let kind: Kind
}

// MARK: - Accelerometer Monitor

/// macOS stub — CMMotionManager / accelerometer APIs are not available in native macOS apps.
/// This monitor always reports as unavailable and emits no events.
///
/// On iOS/iPadOS this would use CMMotionManager; on macOS the hardware API is not exposed,
/// so device-moved detection is omitted.
final class AccelerometerMonitor {

    // MARK: - Publisher

    private let subject = PassthroughSubject<AccelerometerEvent, Never>()
    var publisher: AnyPublisher<AccelerometerEvent, Never> { subject.eraseToAnyPublisher() }

    // MARK: - Configuration

    var jerkThreshold: Double = 0.35
    var tiltThreshold: Double = 18.0

    // MARK: - Lifecycle

    /// Always false on macOS — accelerometer is not accessible via a public API.
    var isAvailable: Bool { false }

    func start() {
        AppLogger.shared.info("AccelerometerMonitor: sensor not available on macOS (CMMotionManager unavailable)")
    }

    func stop() {}
}
