import SwiftUI

// MARK: - Menu Bar View
// Shown inside the NSPopover attached to the status bar item.

struct MenuBarView: View {

    @StateObject private var coordinator: MonitoringCoordinator
    @State private var showSettings = false

    init(coordinator: MonitoringCoordinator) {
        _coordinator = StateObject(wrappedValue: coordinator)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            sensorMetrics
            Divider()
            AlertHistoryView()
            Divider()
            footerSection
        }
        .frame(width: 280)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: "shield.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(shieldColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("MacSafe")
                    .font(.system(size: 14, weight: .bold))
                StatusIndicatorView(state: coordinator.state)
            }

            Spacer()

            // Main toggle button
            Button(action: toggleMonitoring) {
                Text(toggleButtonLabel)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(toggleButtonColor.opacity(0.15))
                    .foregroundStyle(toggleButtonColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Sensor Metrics

    private var sensorMetrics: some View {
        HStack(spacing: 16) {
            if coordinator.settings.cameraEnabled {
                MetricView(
                    icon: "camera",
                    label: "Motion",
                    value: String(format: "%.0f%%", coordinator.currentMotionScore * 100),
                    isActive: coordinator.state == .monitoring
                )
            }

            if coordinator.settings.audioEnabled {
                MetricView(
                    icon: "waveform",
                    label: "Audio",
                    value: AudioUtilities.displayString(dBFS: coordinator.currentAudioDB),
                    isActive: coordinator.state == .monitoring
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button(action: openSettings) {
                Label("Settings", systemImage: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            if coordinator.state == .alerting {
                Button("Dismiss Alert") {
                    coordinator.acknowledgeAlert()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.red)
                .buttonStyle(.plain)
            }

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Label("Quit", systemImage: "power")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func toggleMonitoring() {
        switch coordinator.state {
        case .idle:
            coordinator.activate()
        case .monitoring, .alerting:
            coordinator.deactivate()
        case .suspended:
            coordinator.activate()
        }
    }

    private var toggleButtonLabel: String {
        switch coordinator.state {
        case .idle, .suspended: return "Activate"
        case .monitoring:       return "Deactivate"
        case .alerting:         return "Stop"
        }
    }

    private var toggleButtonColor: Color {
        switch coordinator.state {
        case .idle, .suspended: return .green
        case .monitoring:       return .orange
        case .alerting:         return .red
        }
    }

    private var shieldColor: Color {
        switch coordinator.state {
        case .idle:       return .secondary
        case .monitoring: return .green
        case .alerting:   return .red
        case .suspended:  return .orange
        }
    }

    private func openSettings() {
        SettingsWindowController.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Metric View

private struct MetricView: View {
    let icon: String
    let label: String
    let value: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(isActive ? .green : .secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            }
        }
    }
}

#Preview {
    MenuBarView(coordinator: MonitoringCoordinator())
}
