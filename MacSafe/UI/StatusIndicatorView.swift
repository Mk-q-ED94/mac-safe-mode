import SwiftUI

// MARK: - Status Indicator View

struct StatusIndicatorView: View {

    let state: MonitoringState
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 10, height: 10)
                .scaleEffect(pulse ? 1.3 : 1.0)
                .animation(
                    state == .monitoring || state == .alerting
                        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                        : .default,
                    value: pulse
                )
                .onAppear {
                    if state == .monitoring || state == .alerting {
                        pulse = true
                    }
                }
                .onChange(of: state) { newState in
                    pulse = (newState == .monitoring || newState == .alerting)
                }

            Text(stateLabel)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(indicatorColor)
        }
    }

    private var indicatorColor: Color {
        switch state {
        case .idle:       return .secondary
        case .monitoring: return .green
        case .alerting:   return .red
        case .suspended:  return .orange
        }
    }

    private var stateLabel: String {
        switch state {
        case .idle:       return NSLocalizedString("Idle", comment: "")
        case .monitoring: return NSLocalizedString("Monitoring", comment: "")
        case .alerting:   return NSLocalizedString("ALERT", comment: "")
        case .suspended:  return NSLocalizedString("Paused", comment: "")
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        StatusIndicatorView(state: .idle)
        StatusIndicatorView(state: .monitoring)
        StatusIndicatorView(state: .alerting)
        StatusIndicatorView(state: .suspended)
    }
    .padding()
}
