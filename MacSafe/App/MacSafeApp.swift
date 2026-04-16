import SwiftUI

// MARK: - MacSafe App Entry Point

@main
struct MacSafeApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // We use a pure AppDelegate / status bar architecture (no SwiftUI window).
        // Settings: is kept as an empty Settings scene so macOS shows "MacSafe > Settings…"
        // in the menu bar. The actual SettingsWindowController handles the window.
        Settings {
            SettingsView()
        }
    }
}
