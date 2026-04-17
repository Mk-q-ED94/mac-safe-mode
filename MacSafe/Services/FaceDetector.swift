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
/// Filters results against the face whitelist before publishing.
final class FaceDetector {

    // MARK: - Publisher

    private let subject = PassthroughSubject<FaceDetectionResult, Never>()
    var publisher: AnyPublisher<FaceDetectionResult, Never> { subject.eraseToAnyPublisher() }

    // MARK: - Whitelist (thread-safe snapshot updated from main thread)

    private let whitelistLock = NSLock()
    private var _whitelistEntries: [FaceWhitelistEntry] = []

    func setWhitelistEntries(_ entries: [FaceWhitelistEntry]) {
        whitelistLock.lock()
        _whitelistEntries = entries
        whitelistLock.unlock()
    }

    // MARK: - State

    private var config: SensorConfig = .defaults
    private let detectionQueue = DispatchQueue(label: "com.macsafe.face", qos: .utility)

    func updateConfig(_ newConfig: SensorConfig) {
        config = newConfig
    }

    // MARK: - Process Frame

    func process(pixelBuffer: CVPixelBuffer) {
        guard config.faceDetectionEnabled else { return }
        detectionQueue.async { [weak self] in
            self?.detect(pixelBuffer: pixelBuffer)
        }
    }

    // MARK: - Vision Request

    private func detect(pixelBuffer: CVPixelBuffer) {
        let request = VNDetectFaceRectanglesRequest { [weak self] request, error in
            guard let self else { return }
            if let error {
                AppLogger.shared.error("Face detection error: \(error.localizedDescription)")
                return
            }
            let observations = (request.results as? [VNFaceObservation]) ?? []
            guard !observations.isEmpty else { return }

            // Filter whitelisted faces
            self.whitelistLock.lock()
            let entries = self._whitelistEntries
            self.whitelistLock.unlock()

            let unknownFaces: [VNFaceObservation]
            if entries.isEmpty {
                unknownFaces = observations
            } else {
                unknownFaces = observations.filter { face in
                    !FaceWhitelistManager.isWhitelisted(
                        pixelBuffer: pixelBuffer,
                        boundingBox: face.boundingBox,
                        entries: entries
                    )
                }
                if unknownFaces.count < observations.count {
                    let matched = observations.count - unknownFaces.count
                    AppLogger.shared.info("FaceWhitelist: \(matched) whitelisted face(s) suppressed")
                }
            }

            guard !unknownFaces.isEmpty else { return }
            AppLogger.shared.info("Face detected: \(unknownFaces.count) unknown face(s)")
            self.subject.send(FaceDetectionResult(faces: unknownFaces))
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            AppLogger.shared.error("Vision handler error: \(error.localizedDescription)")
        }
    }
}
