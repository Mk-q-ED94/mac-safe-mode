import Foundation
import AVFoundation
import UserNotifications
import Combine

// MARK: - Permission Status

enum PermissionStatus {
    case unknown
    case granted
    case denied
}

// MARK: - Permissions Manager

@MainActor
class PermissionsManager: ObservableObject {

    static let shared = PermissionsManager()

    @Published private(set) var cameraStatus: PermissionStatus = .unknown
    @Published private(set) var microphoneStatus: PermissionStatus = .unknown
    @Published private(set) var notificationStatus: PermissionStatus = .unknown

    var allGranted: Bool {
        cameraStatus == .granted &&
        microphoneStatus == .granted &&
        notificationStatus == .granted
    }

    private init() {
        refreshStatuses()
    }

    // MARK: - Request All Permissions

    func requestAll() async {
        await requestCamera()
        await requestMicrophone()
        await requestNotifications()
    }

    // MARK: - Individual Requests

    func requestCamera() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            cameraStatus = .granted
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraStatus = granted ? .granted : .denied
        default:
            cameraStatus = .denied
        }
    }

    func requestMicrophone() async {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            microphoneStatus = .granted
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            microphoneStatus = granted ? .granted : .denied
        default:
            microphoneStatus = .denied
        }
    }

    func requestNotifications() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            notificationStatus = granted ? .granted : .denied
        } catch {
            notificationStatus = .denied
            AppLogger.shared.error("Notification permission error: \(error.localizedDescription)")
        }
    }

    // MARK: - Refresh

    func refreshStatuses() {
        // Camera
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: cameraStatus = .granted
        case .denied, .restricted: cameraStatus = .denied
        default: cameraStatus = .unknown
        }

        // Microphone
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: microphoneStatus = .granted
        case .denied, .restricted: microphoneStatus = .denied
        default: microphoneStatus = .unknown
        }

        // Notifications
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional: self?.notificationStatus = .granted
                case .denied: self?.notificationStatus = .denied
                default: self?.notificationStatus = .unknown
                }
            }
        }
    }
}
