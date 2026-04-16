import Foundation
import Combine
import CoreVideo

// MARK: - Monitoring Coordinator

/// Central ObservableObject that owns all sensor services, drives the state machine,
/// and coordinates alert delivery. The UI layer observes this object directly.
@MainActor
final class MonitoringCoordinator: ObservableObject {

    // MARK: - Published State

    @Published private(set) var state: MonitoringState = .idle
    @Published private(set) var currentMotionScore: Float = 0.0
    @Published private(set) var currentAudioDB: Float = -160.0

    // MARK: - Services

    private let stateMachine = MonitoringStateMachine()
    private let screenMonitor = ScreenStateMonitor()
    private let idleMonitor = IdleMonitor()
    private let cameraService = CameraService()
    private let motionDetector = MotionDetector()
    private let faceDetector = FaceDetector()
    private let videoRecorder = VideoRecorder()
    private let audioMonitor = AudioMonitor()
    private let accelerometerMonitor = AccelerometerMonitor()
    private let alertService: AlertService
    let settings: AppSettings

    // MARK: - Combine

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Alert Timeout

    private var alertTimeoutTask: Task<Void, Never>?
    private static let alertTimeoutSeconds: TimeInterval = 30.0

    // MARK: - Background Activity Assertion
    //
    // Held while sensors are running.
    //   • Always prevents App Nap (ensures timers and Combine pipelines fire on schedule).
    //   • Optionally also prevents system idle sleep when the user enables that setting,
    //     so the Mac stays awake and keeps monitoring even if it would normally sleep.

    private var monitoringActivity: NSObjectProtocol?

    // MARK: - Init

    init(settings: AppSettings = .shared) {
        self.settings = settings
        self.alertService = AlertService(settings: settings)
        subscribeToSensors()
        applySettings()
        AppLogger.shared.info("MonitoringCoordinator initialized")
    }

    // MARK: - Public Controls

    func activate() {
        processEvent(.manualActivation)
    }

    func deactivate() {
        processEvent(.manualDeactivation)
    }

    func acknowledgeAlert() {
        alertTimeoutTask?.cancel()
        processEvent(.alertAcknowledged)
    }

    // MARK: - Settings Application

    func applySettings() {
        let config = SensorConfig.from(settings)
        motionDetector.updateConfig(config)
        faceDetector.updateConfig(config)
        audioMonitor.updateConfig(config)
        videoRecorder.updateConfig(config)
        idleMonitor.thresholdSeconds = settings.idleTimeoutSeconds
    }

    // MARK: - Event Processing

    private func processEvent(_ event: StateMachineEvent) {
        Task {
            let effect = await stateMachine.send(event)
            let newState = await stateMachine.currentState
            await MainActor.run {
                self.state = newState
                self.handleSideEffect(effect)
            }
        }
    }

    private func handleSideEffect(_ effect: MonitoringStateMachine.SideEffect?) {
        switch effect {
        case .startSensors:
            startSensors()
        case .stopSensors:
            stopSensors()
        case .fireAlert(let type, let score):
            triggerAlert(type: type, score: score)
        case .dismissAlert:
            alertTimeoutTask?.cancel()
        case nil:
            break
        }
    }

    // MARK: - Sensor Lifecycle

    private func startSensors() {
        AppLogger.shared.info("Starting sensors")
        applySettings()

        // Acquire a ProcessInfo activity assertion to:
        //   1. Prevent App Nap — ensures background timers and Combine publishers fire reliably.
        //   2. Optionally prevent system idle sleep — keeps the Mac awake during monitoring.
        let options: ProcessInfo.ActivityOptions = settings.preventSystemSleepWhileMonitoring
            ? [.background, .idleSystemSleepDisabled]
            : [.background]
        monitoringActivity = ProcessInfo.processInfo.beginActivity(
            options: options,
            reason: "MacSafe security monitoring"
        )

        if settings.cameraEnabled {
            cameraService.start()
        }
        if settings.audioEnabled {
            audioMonitor.start()
        }
        if settings.accelerometerEnabled {
            accelerometerMonitor.start()
        }
        idleMonitor.start()
        motionDetector.reset()
    }

    private func stopSensors() {
        AppLogger.shared.info("Stopping sensors")

        // Release the activity assertion — allows App Nap and system sleep to resume normally.
        monitoringActivity = nil

        cameraService.stop()
        audioMonitor.stop()
        accelerometerMonitor.stop()
        idleMonitor.stop()
        motionDetector.reset()
        currentMotionScore = 0.0
        currentAudioDB = -160.0
    }

    // MARK: - Alert Trigger

    private func triggerAlert(type: AlertType, score: Float) {
        AppLogger.shared.info("Triggering alert: \(type.rawValue)")

        // Start video clip save if enabled
        if settings.videoRecordingEnabled {
            videoRecorder.saveClip { [weak self] videoURL in
                let trigger = AlertTrigger(type: type, score: score, videoURL: videoURL)
                Task { @MainActor in
                    self?.alertService.fire(trigger)
                }
            }
        } else {
            let trigger = AlertTrigger(type: type, score: score, videoURL: nil)
            alertService.fire(trigger)
        }

        // Schedule auto-dismiss
        alertTimeoutTask?.cancel()
        alertTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.alertTimeoutSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            processEvent(.alertTimeout)
        }
    }

    // MARK: - Sensor Subscriptions

    private func subscribeToSensors() {
        subscribeToScreenMonitor()
        subscribeToIdleMonitor()
        subscribeToCamera()
        subscribeToAudio()
        subscribeToAccelerometer()
    }

    private func subscribeToScreenMonitor() {
        screenMonitor.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                switch event {
                case .locked:
                    self.handleScreenLock()
                case .unlocked:
                    self.processEvent(.screenUnlocked)
                case .screensaverStarted:
                    self.handleScreenSaverStart()
                case .screensaverStopped:
                    self.processEvent(.screenUnlocked)
                case .displaySleep:
                    self.handleDisplaySleep()
                case .displayWake:
                    self.handleDisplayWake()
                case .lidOpened:
                    self.handleLidOpened()
                }
            }
            .store(in: &cancellables)
    }

    private func subscribeToIdleMonitor() {
        idleMonitor.idlePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self, self.settings.activateOnIdle else { return }
                self.processEvent(.idleThresholdReached)
            }
            .store(in: &cancellables)

        idleMonitor.activityPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.processEvent(.userActivityDetected)
            }
            .store(in: &cancellables)
    }

    private func subscribeToCamera() {
        cameraService.framePublisher
            .sink { [weak self] pixelBuffer in
                guard let self else { return }

                // Feed video recorder
                // VideoRecorder needs CMSampleBuffer, not CVPixelBuffer
                // — this is handled in CameraService for full integration
                // For now, feed motion/face directly

                // Motion detection (runs on captureQueue)
                self.motionDetector.process(pixelBuffer: pixelBuffer)

                // Feed face detector only above pre-threshold
                if self.currentMotionScore > SensorConfig.from(self.settings).motionPreThreshold {
                    self.faceDetector.process(pixelBuffer: pixelBuffer)
                }
            }
            .store(in: &cancellables)

        motionDetector.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                self?.currentMotionScore = result.score
                if result.isTriggered {
                    self?.processEvent(.motionDetected(score: result.score))
                }
            }
            .store(in: &cancellables)

        faceDetector.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                if result.hasFaces, let face = result.largestFace {
                    self?.processEvent(.faceDetected(boundingBox: face.boundingBox))
                }
            }
            .store(in: &cancellables)
    }

    private func subscribeToAudio() {
        audioMonitor.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.currentAudioDB = event.dBFS
                if event.isTriggered {
                    self?.processEvent(.loudSoundDetected(dBFS: event.dBFS))
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Screen/Screensaver/Sleep Helpers

    private func handleScreenLock() {
        guard settings.activateOnScreenLock else { return }
        processEvent(.screenLocked)
    }

    private func handleScreenSaverStart() {
        guard settings.activateOnScreenSaver else { return }
        processEvent(.screenSaverStarted)
    }

    /// Called when the display goes to sleep.
    /// Treat as a lock event so sensors activate — the camera will be interrupted
    /// by the OS but the microphone and accelerometer continue working.
    private func handleDisplaySleep() {
        guard settings.activateOnScreenLock else { return }
        processEvent(.screenLocked)
    }

    /// Called when the display wakes from sleep (including after system sleep).
    ///
    /// **Bug fix**: Previously this always sent `userActivityDetected`, which would
    /// stop sensors even when the screen is still locked (e.g. after waking from sleep
    /// with the lock screen showing). Now we check whether the screen is actually
    /// unlocked before stopping sensors.
    private func handleDisplayWake() {
        if screenMonitor.isScreenLocked() {
            // Screen is still locked — the Mac woke from sleep but hasn't been unlocked.
            // Keep sensors running. If somehow we drifted to idle (race condition),
            // re-activate immediately.
            AppLogger.shared.info("Display woke while screen still locked — keeping sensors active")
            if state == .idle {
                processEvent(.screenLocked)
            }
        } else {
            // Screen is unlocked — user is present, stop monitoring.
            processEvent(.userActivityDetected)
        }
    }

    private func handleLidOpened() {
        guard settings.lidOpenDetectionEnabled else { return }
        // Lid open fires regardless of whether we're already in monitoring state —
        // the state machine handles the no-op if we're already alerting.
        processEvent(.lidOpened)
    }

    private func subscribeToAccelerometer() {
        accelerometerMonitor.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self, self.settings.accelerometerEnabled else { return }
                switch event.kind {
                case .jerk(let g):
                    AppLogger.shared.info("Jerk alert: \(String(format: "%.2f", g))g")
                case .tilt(let deg):
                    AppLogger.shared.info("Tilt alert: \(String(format: "%.1f", deg))°")
                }
                self.processEvent(.deviceMoved)
            }
            .store(in: &cancellables)
    }
}
