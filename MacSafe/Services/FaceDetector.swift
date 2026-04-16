import Foundation
import Vision
import CoreVideo
import Combine

// MARK: - Face Detection Result

struct FaceDetectionResult {
    let faces: [VNFaceObservation]
    var hasFaces: Bool { !faces.isEmpty }
    var largestFace: VNFaceObservation? {
        faces.max { $0.boundingBox.width < $1.boundingBox.width }
    }
}

// MARK: - Face Detector

/// Detects faces in camera frames using Vision framework.
/// Only runs when motion pre-threshold is exceeded to save CPU.
final class FaceDetector {

    // MARK: - Publisher

    private let subject = PassthroughSubject<FaceDetectionResult, Never>()
    var publisher: AnyPublisher<FaceDetectionResult, Never> { subject.eraseToAnyPublisher() }

    // MARK: - State

    private var config: SensorConfig = .defaults
    private let detectionQueue = DispatchQueue(label: "com.macsafe.face", qos: .utility)

    // MARK: - Configuration

    func updateConfig(_ newConfig: SensorConfig) {
        config = newConfig
    }

    // MARK: - Process Frame

    /// Call this when motion pre-threshold is exceeded.
    func process(pixelBuffer: CVPixelBuffer) {
        guard config.faceDetectionEnabled else { return }

        detectionQueue.async { [weak self] in
            self?.detect(pixelBuffer: pixelBuffer)
        }
    }

    // MARK: - Vision Request

    private func detect(pixelBuffer: CVPixelBuffer) {
        let request = VNDetectFaceRectanglesRequest { [weak self] request, error in
            if let error {
                AppLogger.shared.error("Face detection error: \(error.localizedDescription)")
                return
            }
            let observations = request.results as? [VNFaceObservation] ?? []
            let result = FaceDetectionResult(faces: observations)
            if result.hasFaces {
                AppLogger.shared.info("Face detected: \(observations.count) face(s)")
                self?.subject.send(result)
            }
        }

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )
        do {
            try handler.perform([request])
        } catch {
            AppLogger.shared.error("Vision handler error: \(error.localizedDescription)")
        }
    }
}
