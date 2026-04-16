import SwiftUI

// MARK: - Alert History View

struct AlertHistoryView: View {

    @ObservedObject private var history = AlertHistory.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow

            if history.events.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(history.events) { event in
                            AlertEventRow(event: event)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
    }

    private var headerRow: some View {
        HStack {
            Text("Recent Alerts")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()

            if !history.events.isEmpty {
                Button("Clear") {
                    history.clear()
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var emptyState: some View {
        Text("No alerts yet")
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 20)
    }
}

// MARK: - Alert Event Row

private struct AlertEventRow: View {

    let event: AlertEvent

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: event.type.systemImageName)
                .frame(width: 18)
                .foregroundStyle(typeColor)
                .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(event.type.localizedTitle)
                    .font(.system(size: 12, weight: .medium))

                Text(relativeTime(event.timestamp))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let videoURL = event.videoURL {
                Button(action: { NSWorkspace.shared.open(videoURL) }) {
                    Image(systemName: "play.circle")
                        .foregroundStyle(.blue)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("Open video clip")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var typeColor: Color {
        switch event.type {
        case .motion:      return .blue
        case .face:        return .orange
        case .audio:       return .purple
        case .lidOpened:   return .yellow
        case .deviceMoved: return .red
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    AlertHistoryView()
        .frame(width: 280)
}
