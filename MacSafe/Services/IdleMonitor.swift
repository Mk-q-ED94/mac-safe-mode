import Foundation
import IOKit
import Combine

// MARK: - Idle Monitor

/// Polls system idle time every 10 seconds and publishes when the idle threshold is crossed.
final class IdleMonitor {

    // MARK: - Publishers

    private let idleSubject = PassthroughSubject<Void, Never>()
    private let activitySubject = PassthroughSubject<Void, Never>()

    /// Fires when the user has been idle longer than `thresholdSeconds`.
    var idlePublisher: AnyPublisher<Void, Never> { idleSubject.eraseToAnyPublisher() }

    /// Fires when the user returns from idle (activity detected after idle period).
    var activityPublisher: AnyPublisher<Void, Never> { activitySubject.eraseToAnyPublisher() }

    // MARK: - State

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.macsafe.idle", qos: .utility)
    private var wasIdle = false

    var thresholdSeconds: TimeInterval = 300.0

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 10, repeating: 10)
        t.setEventHandler { [weak self] in self?.check() }
        t.resume()
        timer = t
        AppLogger.shared.info("IdleMonitor started (threshold: \(thresholdSeconds)s)")
    }

    func stop() {
        timer?.cancel()
        timer = nil
        wasIdle = false
        AppLogger.shared.info("IdleMonitor stopped")
    }

    // MARK: - IOKit Idle Time

    func currentIdleSeconds() -> TimeInterval {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem"),
            &iterator
        ) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        defer { IOObjectRelease(entry) }
        guard entry != IO_OBJECT_NULL else { return 0 }

        var properties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(
            entry, &properties, kCFAllocatorDefault, 0
        )
        guard result == KERN_SUCCESS,
              let dict = properties?.takeRetainedValue() as? [String: Any],
              let hidIdleNanoseconds = dict["HIDIdleTime"] as? UInt64
        else { return 0 }

        return TimeInterval(hidIdleNanoseconds) / 1_000_000_000.0
    }

    // MARK: - Check

    private func check() {
        let idle = currentIdleSeconds()
        let isIdle = idle >= thresholdSeconds

        if isIdle && !wasIdle {
            wasIdle = true
            AppLogger.shared.info("Idle threshold reached (\(idle)s)")
            idleSubject.send()
        } else if !isIdle && wasIdle {
            wasIdle = false
            AppLogger.shared.info("Activity detected after idle")
            activitySubject.send()
        }
    }
}
