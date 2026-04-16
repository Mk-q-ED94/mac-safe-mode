import Foundation
import CoreImage
import CoreVideo
import Combine

// MARK: - Motion Detection Result

struct MotionResult {
    let score: Float        // 0.0 (no motion) to 1.0 (maximum motion)
    let isTriggered: Bool   // true when score exceeds threshold
}

// MARK: - Motion Detector

/// Frame-differencing motion detector using CoreImage.
/// Runs on the caller's thread (captureQueue from CameraService).
final class MotionDetector {

    // MARK: - Publisher

    private let subject = PassthroughSubject<MotionResult, Never>()
    var publisher: AnyPublisher<MotionResult, Never> { subject.eraseToAnyPublisher() }

    // MARK: - State

    private var previousFrame: CIImage?
    private var smoothedScore: Float = 0.0
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private var config: SensorConfig = .defaults

    // MARK: - Configuration

    func updateConfig(_ newConfig: SensorConfig) {
        config = newConfig
    }

    func reset() {
        previousFrame = nil
        smoothedScore = 0.0
    }

    // MARK: - Process Frame

    func process(pixelBuffer: CVPixelBuffer) {
        let current = CIImage(cvPixelBuffer: pixelBuffer)
        let downsampled = downsample(current)

        defer { previousFrame = downsampled }

        guard let previous = previousFrame else { return }

        let score = computeMotionScore(current: downsampled, previous: previous)

        // Temporal smoothing: reduces single-frame noise spikes
        smoothedScore = 0.7 * smoothedScore + 0.3 * score

        let triggered = smoothedScore > config.motionThreshold
        subject.send(MotionResult(score: smoothedScore, isTriggered: triggered))
    }

    // MARK: - Pipeline

    private func downsample(_ image: CIImage) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        let targetWidth: CGFloat = 160
        let scale = targetWidth / extent.width
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    private func toGrayscale(_ image: CIImage) -> CIImage {
        // Use luminance weights to convert to grayscale
        let colorMatrix = CIFilter.colorMatrix()
        colorMatrix.inputImage = image
        // R channel gets luminance weights for all output channels
        colorMatrix.rVector = CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0)
        colorMatrix.gVector = CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0)
        colorMatrix.bVector = CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0)
        colorMatrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        colorMatrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        return colorMatrix.outputImage ?? image
    }

    private func absoluteDifference(a: CIImage, b: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CIColorAbsoluteDifference") else {
            // Fallback: use subtract blend mode
            let subtractFilter = CIFilter.subtractBlendMode()
            subtractFilter.inputImage = a
            subtractFilter.backgroundImage = b
            return subtractFilter.outputImage ?? a
        }
        filter.setValue(a, forKey: kCIInputImageKey)
        filter.setValue(b, forKey: "inputImage2")
        return filter.outputImage ?? a
    }

    private func averageLuminance(_ image: CIImage) -> Float {
        let extent = image.extent
        guard !extent.isInfinite, extent.width > 0, extent.height > 0 else { return 0 }

        // Use CIAreaAverage to get a 1x1 pixel with the average color
        let averageFilter = CIFilter.areaAverage()
        averageFilter.inputImage = image
        averageFilter.extent = extent

        guard let outputImage = averageFilter.outputImage else { return 0 }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            outputImage,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        // R channel (index 0) holds grayscale luminance
        return Float(pixel[0]) / 255.0
    }

    private func computeMotionScore(current: CIImage, previous: CIImage) -> Float {
        let grayA = toGrayscale(current)
        let grayB = toGrayscale(previous)
        let diff = absoluteDifference(a: grayA, b: grayB)
        return averageLuminance(diff)
    }
}
