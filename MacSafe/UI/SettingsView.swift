import SwiftUI

// MARK: - Settings View

struct SettingsView: View {

    @StateObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            activationSection
            sensorsSection
            sensitivitySection
            videoSection
            pushoverSection
            aboutSection
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460, height: 560)
    }

    // MARK: - Activation

    private var activationSection: some View {
        Section("Automatic Activation") {
            Toggle("Activate when screen locks", isOn: $settings.activateOnScreenLock)
            Toggle("Activate when screensaver starts", isOn: $settings.activateOnScreenSaver)

            HStack {
                Toggle("Activate when idle for", isOn: $settings.activateOnIdle)
                Spacer()
                if settings.activateOnIdle {
                    Picker("", selection: $settings.idleTimeoutSeconds) {
                        Text("1 min").tag(60.0)
                        Text("5 min").tag(300.0)
                        Text("10 min").tag(600.0)
                        Text("30 min").tag(1800.0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 90)
                }
            }

            Toggle("Launch MacSafe at login", isOn: $settings.launchAtLogin)

            VStack(alignment: .leading, spacing: 2) {
                Toggle("Prevent system sleep while monitoring", isOn: $settings.preventSystemSleepWhileMonitoring)
                Text("Keeps the Mac awake so the microphone and accelerometer stay active. The camera may still be restricted by macOS when the display is off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Sensors

    private var sensorsSection: some View {
        Section("Sensors") {
            Toggle("Camera (motion & face detection)", isOn: $settings.cameraEnabled)

            if settings.cameraEnabled {
                Toggle("Face detection", isOn: $settings.faceDetectionEnabled)
                    .padding(.leading, 16)
            }

            Toggle("Microphone (sound detection)", isOn: $settings.audioEnabled)

            VStack(alignment: .leading, spacing: 2) {
                Toggle("Lid open detection", isOn: $settings.lidOpenDetectionEnabled)
                Text("Alert when the MacBook lid is physically opened while monitoring.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Toggle("Motion sensor (accelerometer)", isOn: $settings.accelerometerEnabled)
                    if !accelerometerAvailable {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .help("Requires Apple Silicon MacBook (M1 or later)")
                    }
                }
                Text("Alert when the device is picked up or tilted. Catches theft from behind the camera. Apple Silicon MacBooks only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accelerometerAvailable: Bool {
        AccelerometerMonitor().isAvailable
    }

    // MARK: - Sensitivity

    private var sensitivitySection: some View {
        Section("Sensitivity") {
            if settings.cameraEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Motion threshold")
                        Spacer()
                        Text(String(format: "%.0f%%", settings.motionThreshold * 100))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.motionThreshold, in: 0.02...0.3, step: 0.01)
                    Text("Lower = more sensitive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if settings.audioEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Audio threshold")
                        Spacer()
                        Text(String(format: "%.0f dBFS", settings.audioThresholdDB))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.audioThresholdDB, in: -60.0 ... -10.0, step: 1.0)
                    Text("Higher (less negative) = louder sounds only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Video Recording

    private var videoSection: some View {
        Section("Video Recording") {
            Toggle("Save video clips on alert", isOn: $settings.videoRecordingEnabled)

            if settings.videoRecordingEnabled {
                HStack {
                    Text("Pre-roll buffer")
                    Spacer()
                    Picker("", selection: $settings.preRollSeconds) {
                        Text("5 sec").tag(5.0)
                        Text("10 sec").tag(10.0)
                        Text("15 sec").tag(15.0)
                        Text("30 sec").tag(30.0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 90)
                }

                HStack {
                    Text("Post-roll duration")
                    Spacer()
                    Picker("", selection: $settings.postRollSeconds) {
                        Text("5 sec").tag(5.0)
                        Text("10 sec").tag(10.0)
                        Text("15 sec").tag(15.0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 90)
                }

                Button("Open Recordings Folder") {
                    openRecordingsFolder()
                }
                .buttonStyle(.link)
            }
        }
    }

    // MARK: - Pushover

    private var pushoverSection: some View {
        Section("Mobile Push Notifications (Pushover)") {
            Toggle("Enable Pushover notifications", isOn: $settings.pushoverEnabled)

            if settings.pushoverEnabled {
                LabeledContent("User Key") {
                    SecureField("Your Pushover user key", text: $settings.pushoverUserKey)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent("API Token") {
                    SecureField("App API token", text: $settings.pushoverApiToken)
                        .textFieldStyle(.roundedBorder)
                }

                if settings.pushoverConfigured {
                    Label("Pushover configured", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Text("Enter both keys to enable mobile alerts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Link("Get Pushover at pushover.net →",
                     destination: URL(string: "https://pushover.net")!)
                    .font(.caption)
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version") {
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            }
            LabeledContent("macOS required") {
                Text("13.0 or later")
            }
        }
    }

    // MARK: - Helpers

    private func openRecordingsFolder() {
        let moviesURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
        let folderURL = moviesURL.appendingPathComponent("MacSafe", isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folderURL)
    }
}

#Preview {
    SettingsView()
}
