import SwiftUI

// MARK: - Settings View

struct SettingsView: View {

    @StateObject private var settings = AppSettings.shared
    @ObservedObject private var whitelist = FaceWhitelistManager.shared

    // Face enrollment sheet state
    @State private var showingEnrollSheet = false
    @State private var pendingImage: NSImage?
    @State private var newPersonName = ""
    @State private var enrollError: String?
    @State private var isEnrolling = false

    var body: some View {
        Form {
            activationSection
            sensorsSection
            whitelistSection
            sensitivitySection
            videoSection
            pushoverSection
            aboutSection
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460, height: 620)
        .sheet(isPresented: $showingEnrollSheet) { enrollSheet }
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

    // MARK: - Face Whitelist

    private var whitelistSection: some View {
        Section("Face Whitelist") {
            Toggle("Ignore recognized faces", isOn: $settings.faceWhitelistEnabled)

            if settings.faceWhitelistEnabled {
                if whitelist.entries.isEmpty {
                    Text("No faces enrolled. Add a photo below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(whitelist.entries) { entry in
                        HStack(spacing: 8) {
                            if let img = entry.thumbnail {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 32, height: 32)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "person.circle")
                                    .frame(width: 32, height: 32)
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.name)
                            Spacer()
                            Button {
                                whitelist.removeEntry(id: entry.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button("Add Person from Photo…") { pickPhoto() }

                Text("Select a photo showing one clear, front-facing face. Recognition uses Apple Vision — accuracy may vary.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Enroll Sheet

    private var enrollSheet: some View {
        VStack(spacing: 16) {
            Text("Add Person")
                .font(.headline)

            if let img = pendingImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            TextField("Name (e.g. John)", text: $newPersonName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)

            if let err = enrollError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 220)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    showingEnrollSheet = false
                    pendingImage = nil
                    newPersonName = ""
                    enrollError = nil
                }
                Button("Enroll") {
                    guard let image = pendingImage else { return }
                    isEnrolling = true
                    enrollError = nil
                    Task {
                        let err = await whitelist.addEntry(name: newPersonName, image: image)
                        isEnrolling = false
                        if let err {
                            enrollError = err
                        } else {
                            showingEnrollSheet = false
                            pendingImage = nil
                            newPersonName = ""
                        }
                    }
                }
                .disabled(newPersonName.trimmingCharacters(in: .whitespaces).isEmpty || isEnrolling)
            }

            if isEnrolling {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(24)
        .frame(width: 300)
    }

    // MARK: - Photo Picker

    private func pickPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a photo with one clear face"
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url) else { return }
        pendingImage = image
        newPersonName = ""
        enrollError = nil
        showingEnrollSheet = true
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
