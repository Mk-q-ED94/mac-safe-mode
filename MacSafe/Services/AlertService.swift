import Foundation
import UserNotifications
import AppKit
import Combine

// MARK: - Alert Trigger

struct AlertTrigger {
    let type: AlertType
    let score: Float
    let videoURL: URL?
}

// MARK: - Alert Service

/// Handles alert delivery: local notification, system sound, Pushover push, and history logging.
@MainActor
final class AlertService: ObservableObject {

    // MARK: - Dependencies

    private let history = AlertHistory.shared
    private let settings: AppSettings

    // MARK: - State

    private var lastAlertTime: Date?
    private let minimumAlertInterval: TimeInterval = 10.0  // Debounce repeated alerts

    // MARK: - Init

    init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - Fire Alert

    func fire(_ trigger: AlertTrigger) {
        // Debounce
        if let last = lastAlertTime, Date().timeIntervalSince(last) < minimumAlertInterval {
            return
        }
        lastAlertTime = Date()

        let event = AlertEvent(type: trigger.type, score: trigger.score, videoURL: trigger.videoURL)
        history.append(event)

        sendLocalNotification(for: trigger.type)
        playAlertSound()
        sendPushoverIfConfigured(for: trigger.type)

        AppLogger.shared.info("Alert fired: \(trigger.type.rawValue) (score: \(trigger.score))")
    }

    // MARK: - Local Notification

    private func sendLocalNotification(for type: AlertType) {
        let content = UNMutableNotificationContent()
        content.title = "MacSafe — \(type.localizedTitle)"
        content.body = notificationBody(for: type)
        content.sound = .defaultCritical
        content.interruptionLevel = .critical

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil   // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLogger.shared.error("Notification error: \(error.localizedDescription)")
            }
        }
    }

    private func notificationBody(for type: AlertType) -> String {
        switch type {
        case .motion: return "Movement was detected near your Mac."
        case .face:   return "A face was detected near your locked Mac."
        case .audio:  return "A loud sound was detected near your Mac."
        }
    }

    // MARK: - System Sound

    private func playAlertSound() {
        // Use the system "Glass" sound — no bundled audio file required
        NSSound(named: NSSound.Name("Glass"))?.play()
    }

    // MARK: - Pushover

    private func sendPushoverIfConfigured(for type: AlertType) {
        guard settings.pushoverConfigured else { return }

        PushoverService.send(
            title: "MacSafe Alert",
            message: notificationBody(for: type),
            userKey: settings.pushoverUserKey,
            apiToken: settings.pushoverApiToken,
            priority: .high
        )
    }

    // MARK: - Dismiss / History

    func clearHistory() {
        history.clear()
    }
}
