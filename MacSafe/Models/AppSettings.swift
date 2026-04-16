import Foundation
import ServiceManagement

// MARK: - App Settings

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // MARK: - Sensor Thresholds

    @Published var motionThreshold: Double {
        didSet { UserDefaults.standard.set(motionThreshold, forKey: "motionThreshold") }
    }

    @Published var audioThresholdDB: Double {
        didSet { UserDefaults.standard.set(audioThresholdDB, forKey: "audioThresholdDB") }
    }

    @Published var idleTimeoutSeconds: Double {
        didSet { UserDefaults.standard.set(idleTimeoutSeconds, forKey: "idleTimeoutSeconds") }
    }

    // MARK: - Sensor Toggles

    @Published var cameraEnabled: Bool {
        didSet { UserDefaults.standard.set(cameraEnabled, forKey: "cameraEnabled") }
    }

    @Published var audioEnabled: Bool {
        didSet { UserDefaults.standard.set(audioEnabled, forKey: "audioEnabled") }
    }

    @Published var faceDetectionEnabled: Bool {
        didSet { UserDefaults.standard.set(faceDetectionEnabled, forKey: "faceDetectionEnabled") }
    }

    /// Alert when the MacBook lid is physically opened while monitoring is active.
    @Published var lidOpenDetectionEnabled: Bool {
        didSet { UserDefaults.standard.set(lidOpenDetectionEnabled, forKey: "lidOpenDetectionEnabled") }
    }

    /// Alert when the device is physically moved/picked up (Apple Silicon MacBooks only).
    @Published var accelerometerEnabled: Bool {
        didSet { UserDefaults.standard.set(accelerometerEnabled, forKey: "accelerometerEnabled") }
    }

    // MARK: - Activation Triggers

    @Published var activateOnScreenLock: Bool {
        didSet { UserDefaults.standard.set(activateOnScreenLock, forKey: "activateOnScreenLock") }
    }

    @Published var activateOnScreenSaver: Bool {
        didSet { UserDefaults.standard.set(activateOnScreenSaver, forKey: "activateOnScreenSaver") }
    }

    @Published var activateOnIdle: Bool {
        didSet { UserDefaults.standard.set(activateOnIdle, forKey: "activateOnIdle") }
    }

    // MARK: - Pushover Notifications

    @Published var pushoverUserKey: String {
        didSet { UserDefaults.standard.set(pushoverUserKey, forKey: "pushoverUserKey") }
    }

    @Published var pushoverApiToken: String {
        didSet { UserDefaults.standard.set(pushoverApiToken, forKey: "pushoverApiToken") }
    }

    @Published var pushoverEnabled: Bool {
        didSet { UserDefaults.standard.set(pushoverEnabled, forKey: "pushoverEnabled") }
    }

    // MARK: - Video Recording

    @Published var videoRecordingEnabled: Bool {
        didSet { UserDefaults.standard.set(videoRecordingEnabled, forKey: "videoRecordingEnabled") }
    }

    @Published var preRollSeconds: Double {
        didSet { UserDefaults.standard.set(preRollSeconds, forKey: "preRollSeconds") }
    }

    @Published var postRollSeconds: Double {
        didSet { UserDefaults.standard.set(postRollSeconds, forKey: "postRollSeconds") }
    }

    // MARK: - Launch at Login

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            updateLaunchAtLogin(launchAtLogin)
        }
    }

    // MARK: - Sleep Prevention

    /// When true, MacSafe holds an `idleSystemSleepDisabled` power assertion while
    /// sensors are active, preventing the Mac from entering system idle sleep.
    /// This allows the accelerometer and microphone to keep detecting threats even
    /// if the Mac would otherwise sleep. The camera and display are still allowed
    /// to sleep by the OS (hardware restriction when the display is off).
    @Published var preventSystemSleepWhileMonitoring: Bool {
        didSet { UserDefaults.standard.set(preventSystemSleepWhileMonitoring, forKey: "preventSystemSleepWhileMonitoring") }
    }

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard

        motionThreshold = defaults.object(forKey: "motionThreshold") as? Double ?? 0.08
        audioThresholdDB = defaults.object(forKey: "audioThresholdDB") as? Double ?? -30.0
        idleTimeoutSeconds = defaults.object(forKey: "idleTimeoutSeconds") as? Double ?? 300.0

        cameraEnabled = defaults.object(forKey: "cameraEnabled") as? Bool ?? true
        audioEnabled = defaults.object(forKey: "audioEnabled") as? Bool ?? true
        faceDetectionEnabled = defaults.object(forKey: "faceDetectionEnabled") as? Bool ?? true
        lidOpenDetectionEnabled = defaults.object(forKey: "lidOpenDetectionEnabled") as? Bool ?? true
        accelerometerEnabled = defaults.object(forKey: "accelerometerEnabled") as? Bool ?? true

        activateOnScreenLock = defaults.object(forKey: "activateOnScreenLock") as? Bool ?? true
        activateOnScreenSaver = defaults.object(forKey: "activateOnScreenSaver") as? Bool ?? true
        activateOnIdle = defaults.object(forKey: "activateOnIdle") as? Bool ?? true

        pushoverUserKey = defaults.string(forKey: "pushoverUserKey") ?? ""
        pushoverApiToken = defaults.string(forKey: "pushoverApiToken") ?? ""
        pushoverEnabled = defaults.object(forKey: "pushoverEnabled") as? Bool ?? false

        videoRecordingEnabled = defaults.object(forKey: "videoRecordingEnabled") as? Bool ?? true
        preRollSeconds = defaults.object(forKey: "preRollSeconds") as? Double ?? 10.0
        postRollSeconds = defaults.object(forKey: "postRollSeconds") as? Double ?? 5.0

        launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? false
        preventSystemSleepWhileMonitoring = defaults.object(forKey: "preventSystemSleepWhileMonitoring") as? Bool ?? false
    }

    // MARK: - Helpers

    var pushoverConfigured: Bool {
        !pushoverUserKey.isEmpty && !pushoverApiToken.isEmpty && pushoverEnabled
    }

    private func updateLaunchAtLogin(_ enable: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enable {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                AppLogger.shared.error("Launch at login error: \(error.localizedDescription)")
            }
        }
    }
}
