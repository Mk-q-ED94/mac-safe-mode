import Foundation
import AVFoundation
import Accelerate
import Combine

// MARK: - Audio Event

struct AudioLevelEvent {
    let rms: Float
    let dBFS: Float
    let isTriggered: Bool
}

// MARK: - Audio Monitor

/// Monitors microphone input levels using AVAudioEngine.
/// Publishes AudioLevelEvent when sound exceeds the configured threshold.
final class AudioMonitor {

    // MARK: - Publisher

    private let subject = PassthroughSubject<AudioLevelEvent, Never>()
    var publisher: AnyPublisher<AudioLevelEvent, Never> { subject.eraseToAnyPublisher() }

    // MARK: - AVAudioEngine

    private let engine = AVAudioEngine()
    private var config: SensorConfig = .defaults
    private var isRunning = false

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        do {
            try configureEngine()
            try engine.start()
            isRunning = true
            AppLogger.shared.info("AudioMonitor started")
        } catch {
            AppLogger.shared.error("AudioMonitor start failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard isRunning else { return }
        NotificationCenter.default.removeObserver(self, name: .AVAudioEngineConfigurationChange, object: engine)
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        AppLogger.shared.info("AudioMonitor stopped")
    }

    func updateConfig(_ newConfig: SensorConfig) {
        config = newConfig
    }

    // MARK: - Configuration

    private func configureEngine() throws {
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }
        engine.prepare()

        // AVAudioEngineConfigurationChange fires when the audio hardware changes —
        // for example, when the default microphone switches (e.g. Bluetooth headset
        // connects/disconnects, or the system audio session is reset after sleep).
        // We need to rebuild the tap and restart the engine to keep monitoring.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigChange(_:)),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )
    }

    @objc private func handleEngineConfigChange(_ notification: Notification) {
        guard isRunning else { return }
        AppLogger.shared.info("AudioMonitor: engine configuration changed — rebuilding tap and restarting")
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        do {
            try configureEngine()
            try engine.start()
        } catch {
            AppLogger.shared.error("AudioMonitor restart after config change failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Process Audio Buffer

    private func process(buffer: AVAudioPCMBuffer) {
        guard config.audioEnabled,
              let channelData = buffer.floatChannelData?[0]
        else { return }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let rms = AudioUtilities.rms(from: channelData, count: frameCount)
        let dBFS = AudioUtilities.dBFS(from: rms)
        let triggered = dBFS > config.audioThresholdDB

        if triggered {
            AppLogger.shared.info("Loud sound detected: \(AudioUtilities.displayString(dBFS: dBFS))")
        }

        subject.send(AudioLevelEvent(rms: rms, dBFS: dBFS, isTriggered: triggered))
    }
}
