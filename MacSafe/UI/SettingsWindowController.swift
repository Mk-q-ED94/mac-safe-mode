import AppKit
import SwiftUI

// MARK: - Settings Window Controller

final class SettingsWindowController: NSWindowController {

    // MARK: - Singleton

    static let shared: SettingsWindowController = {
        let hostingView = NSHostingView(rootView: SettingsView())
        hostingView.frame = NSRect(x: 0, y: 0, width: 460, height: 560)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacSafe Settings"
        window.contentView = hostingView
        window.center()
        window.setFrameAutosaveName("MacSafeSettings")
        window.isReleasedWhenClosed = false

        return SettingsWindowController(window: window)
    }()

    // MARK: - Show

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
