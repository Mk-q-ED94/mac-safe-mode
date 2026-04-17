import Foundation
import AppKit
import Combine
import IOKit
import CoreGraphics

// MARK: - Screen State Monitor

/// Publishes ScreenEvent values when the display locks, unlocks, screensaver starts/stops,
/// or the MacBook lid is physically opened.
final class ScreenStateMonitor {

    // MARK: - Publisher

    private let subject = PassthroughSubject<ScreenEvent, Never>()
    var publisher: AnyPublisher<ScreenEvent, Never> { subject.eraseToAnyPublisher() }

    // MARK: - Lid State Tracking

    /// Records lid state the last time the display slept or the screen locked.
    /// Used to detect the closed→open transition on wake.
    private var lidWasClosedAtSleep = false

    // MARK: - Lifecycle

    init() {
        registerDistributedNotifications()
        registerWorkspaceNotifications()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Distributed Notifications (Screen Lock)

    private func registerDistributedNotifications() {
        let center = DistributedNotificationCenter.default()

        center.addObserver(
            self,
            selector: #selector(handleScreenLocked),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )

        center.addObserver(
            self,
            selector: #selector(handleScreenUnlocked),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
    }

    // MARK: - NSWorkspace Notifications (Screensaver, Display Sleep)

    private func registerWorkspaceNotifications() {
        let center = NSWorkspace.shared.notificationCenter

        // macOS 14+ removed screensaverDidLaunchNotification / screensaverDidTerminateNotification.
        // Use private notification names that still fire on macOS 14+.
        #if compiler(>=5.9)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenSaverStart),
            name: NSNotification.Name("com.apple.screensaver.didstart"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenSaverStop),
            name: NSNotification.Name("com.apple.screensaver.didstop"),
            object: nil
        )
        #else
        center.addObserver(
            self,
            selector: #selector(handleScreenSaverStart),
            name: NSWorkspace.screensaverDidLaunchNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleScreenSaverStop),
            name: NSWorkspace.screensaverDidTerminateNotification,
            object: nil
        )
        #endif

        center.addObserver(
            self,
            selector: #selector(handleDisplaySleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )

        center.addObserver(
            self,
            selector: #selector(handleDisplayWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }

    // MARK: - Handlers

    @objc private func handleScreenLocked() {
        // Snapshot lid state at lock time so we can detect a lid-open on subsequent wake.
        lidWasClosedAtSleep = isLidClosed()
        AppLogger.shared.info("Screen locked (lid closed: \(lidWasClosedAtSleep))")
        subject.send(.locked)
    }

    @objc private func handleScreenUnlocked() {
        AppLogger.shared.info("Screen unlocked")
        subject.send(.unlocked)
    }

    @objc private func handleScreenSaverStart() {
        AppLogger.shared.info("Screensaver started")
        subject.send(.screensaverStarted)
    }

    @objc private func handleScreenSaverStop() {
        AppLogger.shared.info("Screensaver stopped")
        subject.send(.screensaverStopped)
    }

    @objc private func handleDisplaySleep() {
        // Snapshot lid state at sleep time.
        lidWasClosedAtSleep = isLidClosed()
        AppLogger.shared.info("Display sleep (lid closed: \(lidWasClosedAtSleep))")
        subject.send(.displaySleep)
    }

    @objc private func handleDisplayWake() {
        AppLogger.shared.info("Display wake")

        // Check for lid-open: was closed before sleep/lock, now open.
        if lidWasClosedAtSleep && !isLidClosed() {
            AppLogger.shared.info("Lid opened detected on wake")
            subject.send(.lidOpened)
        }
        lidWasClosedAtSleep = false

        subject.send(.displayWake)
    }

    // MARK: - Screen Lock State

    /// Returns true if the login screen / lock screen is currently shown.
    ///
    /// Reads `CGSSessionScreenIsLocked` from the CoreGraphics session dictionary.
    /// Works in sandboxed apps without special entitlements.
    /// Returns false (conservative: assume unlocked) if the session dict is unavailable.
    func isScreenLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return dict["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    // MARK: - IOKit Lid State

    /// Returns true when the MacBook lid (clamshell) is currently closed.
    ///
    /// Reads `AppleClamshellState` from `IOPMrootDomain` in the IORegistry.
    /// - `kCFBooleanTrue`  → lid is **closed**
    /// - `kCFBooleanFalse` / absent → lid is **open**
    /// On desktop Macs this property is absent, so the method returns false (treat as open).
    func isLidClosed() -> Bool {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }

        guard let value = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? Bool else {
            return false  // Property absent = desktop Mac or lid open
        }
        return value  // true = closed
    }
}
