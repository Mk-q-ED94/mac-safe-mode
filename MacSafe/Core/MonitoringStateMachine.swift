import Foundation

// MARK: - Monitoring State Machine

/// Pure, thread-safe state machine. No side effects — callers observe `currentState`.
actor MonitoringStateMachine {

    // MARK: - State

    private(set) var currentState: MonitoringState = .idle

    // MARK: - Side Effect Descriptor

    enum SideEffect {
        case startSensors
        case stopSensors
        case fireAlert(type: AlertType, score: Float)
        case dismissAlert
    }

    // MARK: - State Transition

    /// Process an event. Returns an optional side effect the coordinator should execute.
    func send(_ event: StateMachineEvent) -> SideEffect? {
        let (nextState, sideEffect) = transition(from: currentState, event: event)
        if nextState != currentState {
            currentState = nextState
        }
        return sideEffect
    }

    // MARK: - Transition Table

    private func transition(
        from state: MonitoringState,
        event: StateMachineEvent
    ) -> (MonitoringState, SideEffect?) {
        switch (state, event) {

        // ── IDLE ──────────────────────────────────────────────────────────────
        case (.idle, .screenLocked),
             (.idle, .screenSaverStarted),
             (.idle, .idleThresholdReached),
             (.idle, .manualActivation):
            return (.monitoring, .startSensors)

        case (.idle, .manualDeactivation):
            return (.suspended, nil)

        // ── MONITORING ────────────────────────────────────────────────────────
        case (.monitoring, .screenUnlocked),
             (.monitoring, .userActivityDetected):
            return (.idle, .stopSensors)

        case (.monitoring, .manualDeactivation):
            return (.suspended, .stopSensors)

        case (.monitoring, .motionDetected(let score)):
            return (.alerting, .fireAlert(type: .motion, score: score))

        case (.monitoring, .faceDetected):
            return (.alerting, .fireAlert(type: .face, score: 1.0))

        case (.monitoring, .loudSoundDetected(let dB)):
            return (.alerting, .fireAlert(type: .audio, score: dB))

        case (.monitoring, .lidOpened):
            return (.alerting, .fireAlert(type: .lidOpened, score: 1.0))

        // ── ALERTING ──────────────────────────────────────────────────────────
        case (.alerting, .screenUnlocked),
             (.alerting, .userActivityDetected):
            return (.idle, .stopSensors)

        case (.alerting, .alertAcknowledged),
             (.alerting, .alertTimeout):
            return (.monitoring, nil)

        case (.alerting, .manualDeactivation):
            return (.suspended, .stopSensors)

        // ── SUSPENDED ─────────────────────────────────────────────────────────
        case (.suspended, .manualActivation):
            return (.monitoring, .startSensors)

        case (.suspended, .screenUnlocked):
            return (.idle, nil)

        // ── UNHANDLED (no-op) ─────────────────────────────────────────────────
        default:
            return (state, nil)
        }
    }
}
