import Foundation

// MARK: - Sensor Configuration Snapshot
// Immutable snapshot passed to sensor services to avoid threading issues with @Published

struct SensorConfig {
    let cameraEnabled: Bool
    let audioEnabled: Bool
    let faceDetectionEnabled: Bool
    let motionThreshold: Float
    let motionPreThreshold: Float   // Lower threshold to activate face detection
    let audioThresholdDB: Float
    let videoRecordingEnabled: Bool
    let preRollSeconds: Double
    let postRollSeconds: Double

    static func from(_ settings: AppSettings) -> SensorConfig {
        SensorConfig(
            cameraEnabled: settings.cameraEnabled,
            audioEnabled: settings.audioEnabled,
            faceDetectionEnabled: settings.faceDetectionEnabled,
            motionThreshold: Float(settings.motionThreshold),
            motionPreThreshold: Float(settings.motionThreshold) * 0.4,
            audioThresholdDB: Float(settings.audioThresholdDB),
            videoRecordingEnabled: settings.videoRecordingEnabled,
            preRollSeconds: settings.preRollSeconds,
            postRollSeconds: settings.postRollSeconds
        )
    }

    static let defaults = SensorConfig(
        cameraEnabled: true,
        audioEnabled: true,
        faceDetectionEnabled: true,
        motionThreshold: 0.08,
        motionPreThreshold: 0.032,
        audioThresholdDB: -30.0,
        videoRecordingEnabled: true,
        preRollSeconds: 10.0,
        postRollSeconds: 5.0
    )
}
