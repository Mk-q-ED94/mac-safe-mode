import Foundation
import CoreMotion
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

/// Detects physical device movement using CoreMotion.
///
/// Works on Apple Silicon MacBooks (M1+) where CMMotionManager.isAccelerometerAvailable = true.
/// Gracefully no-ops on Intel Macs and desktop Macs where the sensor is absent.
///
/// Detection strategy:
///   1. **Baseline phase** (first `baselineSamples` frames): record the at-rest gravity vector.
///   2. **Jerk detection**: instantaneous |magnitude − 1g| > `jerkThreshold`.
///      Catches rapid pick-up from any direction.
///   3. **Tilt detection**: angle between current gravity vector and baseline > `tiltThreshold`.
///      Catches slow tilting / repositioning that avoids the jerk threshold.
final class AccelerometerMonitor {

    // MARK: - Publisher

    private let subject = PassthroughSubject<AccelerometerEvent, Never>()
    var publisher: AnyPublisher<AccelerometerEvent, Never> { subject.eraseToAnyPublisher() }

    // MARK: - CoreMotion

    private let manager = CMMotionManager()

    // MARK: - Configuration

    /// Acceleration magnitude deviation from 1g that triggers a jerk alert.
    var jerkThreshold: Double = 0.35       // 0.35g — noticeable pick-up

    /// Gravity vector rotation angle (degrees) that triggers a tilt alert.
    var tiltThreshold: Double = 18.0       // ~18° — significant repositioning

    /// How many samples to collect at 5 Hz before the baseline is considered stable.
    private let baselineSampleCount = 15   // 3 seconds at 5 Hz

    // MARK: - State

    private var baselineSamples: [SIMD3<Double>] = []
    private var baseline: SIMD3<Double>?
    private var isRunning = false

    // Debounce: suppress repeated triggers within this window (seconds)
    private var lastTriggerTime: Date?
    private let debouncInterval: TimeInterval = 3.0

    // MARK: - Lifecycle

    var isAvailable: Bool { manager.isAccelerometerAvailable }

    func start() {
        guard !isRunning, isAvailable else {
            if !isAvailable {
                AppLogger.shared.info("AccelerometerMonitor: sensor not available on this Mac")
            }
            return
        }

        baseline = nil
        baselineSamples = []
        lastTriggerTime = nil

        manager.accelerometerUpdateInterval = 1.0 / 5.0   // 5 Hz — sufficient, low power
        manager.startAccelerometerUpdates(to: .init()) { [weak self] data, error in
            guard let self, let data else { return }
            self.process(data.acceleration)
        }
        isRunning = true
        AppLogger.shared.info("AccelerometerMonitor started")
    }

    func stop() {
        guard isRunning else { return }
        manager.stopAccelerometerUpdates()
        baseline = nil
        baselineSamples = []
        isRunning = false
        AppLogger.shared.info("AccelerometerMonitor stopped")
    }

    // MARK: - Processing

    private func process(_ acc: CMAcceleration) {
        let vec = SIMD3<Double>(acc.x, acc.y, acc.z)

        // ── Phase 1: baseline collection ────────────────────────────────────
        if baseline == nil {
            baselineSamples.append(vec)
            if baselineSamples.count >= baselineSampleCount {
                // Average the collected samples for a stable gravity reference
                let sum = baselineSamples.reduce(.zero, +)
                baseline = sum / Double(baselineSamples.count)
                AppLogger.shared.info("AccelerometerMonitor: baseline established \(String(format: "(%.3f, %.3f, %.3f)", baseline!.x, baseline!.y, baseline!.z))")
            }
            return
        }

        guard let base = baseline else { return }

        // ── Phase 2: jerk detection ──────────────────────────────────────────
        let magnitude = length(vec)
        let jerk = abs(magnitude - 1.0)

        if jerk > jerkThreshold {
            AppLogger.shared.info("AccelerometerMonitor: jerk detected (Δ\(String(format: "%.2f", jerk))g)")
            fireIfNotDebounced(.jerk(magnitude: magnitude))
            return
        }

        // ── Phase 3: tilt detection ──────────────────────────────────────────
        let baseLen = length(base)
        let curLen  = length(vec)
        guard baseLen > 0.01, curLen > 0.01 else { return }

        let cosAngle = dot(base, vec) / (baseLen * curLen)
        // Clamp to [-1, 1] to guard against floating-point drift before acos
        let clamped = max(-1.0, min(1.0, cosAngle))
        let angleDeg = acos(clamped) * (180.0 / .pi)

        if angleDeg > tiltThreshold {
            AppLogger.shared.info("AccelerometerMonitor: tilt detected (\(String(format: "%.1f", angleDeg))°)")
            fireIfNotDebounced(.tilt(angleDegrees: angleDeg))
        }
    }

    // MARK: - Debounced Fire

    private func fireIfNotDebounced(_ kind: AccelerometerEvent.Kind) {
        let now = Date()
        if let last = lastTriggerTime, now.timeIntervalSince(last) < debouncInterval {
            return
        }
        lastTriggerTime = now
        subject.send(AccelerometerEvent(kind: kind))
    }
}
