import Foundation
import AppKit
import Combine

// MARK: - Screen State Monitor

/// Publishes ScreenEvent values when the display locks, unlocks, or the screensaver starts/stops.
final class ScreenStateMonitor {

    // MARK: - Publisher

    private let subject = PassthroughSubject<ScreenEvent, Never>()
    var publisher: AnyPublisher<ScreenEvent, Never> { subject.eraseToAnyPublisher() }

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
        AppLogger.shared.info("Screen locked")
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
        AppLogger.shared.info("Display sleep")
        subject.send(.displaySleep)
    }

    @objc private func handleDisplayWake() {
        AppLogger.shared.info("Display wake")
        subject.send(.displayWake)
    }
}
