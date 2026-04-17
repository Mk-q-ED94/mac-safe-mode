import AppKit
import SwiftUI
import UserNotifications

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Status Bar

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var coordinator: MonitoringCoordinator?

    // MARK: - App Did Finish Launching

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent Dock icon — LSUIElement=YES in Info.plist handles this at launch,
        // but set accessory here as a safety net.
        NSApp.setActivationPolicy(.accessory)

        // Setup coordinator
        let coord = MonitoringCoordinator(settings: .shared)
        self.coordinator = coord

        // Request permissions on first launch
        Task {
            await PermissionsManager.shared.requestAll()
        }

        // Create status bar item
        setupStatusBar(coordinator: coord)

        // Register for UNUserNotificationCenter delegate
        UNUserNotificationCenter.current().delegate = self

        AppLogger.shared.info("MacSafe launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLogger.shared.info("MacSafe terminating")
    }

    // MARK: - Status Bar Setup

    private func setupStatusBar(coordinator: MonitoringCoordinator) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = item.button {
            button.image = statusImage(for: .idle)
            button.imageScaling = .scaleProportionallyDown
            button.action = #selector(togglePopover)
            button.target = self
        }

        let pop = NSPopover()
        pop.contentSize = NSSize(width: 280, height: 420)
        pop.behavior = .transient
        pop.animates = true
        pop.contentViewController = NSHostingController(
            rootView: MenuBarView(coordinator: coordinator)
        )

        statusItem = item
        popover = pop

        // Update icon when state changes
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            coordinator.$state
                .sink { [weak self] state in
                    self?.statusItem?.button?.image = self?.statusImage(for: state)
                }
                .store(in: &cancellables)
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    // MARK: - Status Icons

    private func statusImage(for state: MonitoringState) -> NSImage? {
        let name: String
        switch state {
        case .idle:       name = "shield"
        case .monitoring: name = "shield.fill"
        case .alerting:   name = "shield.slash.fill"
        case .suspended:  name = "shield.lefthalf.filled"
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "MacSafe")
        image?.isTemplate = (state == .idle || state == .suspended)
        return image
    }

    // MARK: - Combine

    private var cancellables = Set<AnyCancellable>()
}

// MARK: - Combine Import Shim

import Combine

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notifications even when app is in foreground
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Acknowledge alert when user taps notification
        Task { @MainActor in
            coordinator?.acknowledgeAlert()
        }
        completionHandler()
    }
}
