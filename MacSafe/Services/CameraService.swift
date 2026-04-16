import Foundation
import AVFoundation
import CoreVideo
import Combine

// MARK: - Camera Service

/// Manages an AVCaptureSession at 1fps and delivers CVPixelBuffer frames.
final class CameraService: NSObject {

    // MARK: - Publisher

    private let frameSubject = PassthroughSubject<CVPixelBuffer, Never>()
    var framePublisher: AnyPublisher<CVPixelBuffer, Never> { frameSubject.eraseToAnyPublisher() }

    // MARK: - AVFoundation

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let captureQueue = DispatchQueue(label: "com.macsafe.camera", qos: .utility)
    private var isRunning = false

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }

        captureQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.configureSession()
                self.session.startRunning()
                self.isRunning = true
                AppLogger.shared.info("CameraService started")
            } catch {
                AppLogger.shared.error("CameraService start failed: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        captureQueue.async { [weak self] in
            self?.session.stopRunning()
            self?.isRunning = false
            AppLogger.shared.info("CameraService stopped")
        }
    }

    // MARK: - Still Frame Capture

    /// Capture a single still frame synchronously on the capture queue.
    func captureCurrentFrame() -> CVPixelBuffer? {
        // The latest frame is delivered via framePublisher; callers should
        // observe the publisher and cache the last frame themselves.
        // This method is a hook for callers that need synchronous access.
        nil  // Implement in conjunction with lastFrame below if needed
    }

    private(set) var lastFrame: CVPixelBuffer?

    // MARK: - Session Configuration

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .medium

        // Device
        guard let device = bestCamera() else {
            throw CameraError.noDevice
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)

        // Output
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: captureQueue)

        guard session.canAddOutput(videoOutput) else { throw CameraError.cannotAddOutput }
        session.addOutput(videoOutput)

        // Set 1fps to minimize resource usage
        try device.lockForConfiguration()
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 1)
        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 1)
        device.unlockForConfiguration()
    }

    private func bestCamera() -> AVCaptureDevice? {
        // Prefer built-in FaceTime/wide camera
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            return device
        }
        return AVCaptureDevice.default(for: .video)
    }

    // MARK: - Errors

    enum CameraError: Error {
        case noDevice
        case cannotAddInput
        case cannotAddOutput
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = pixelBuffer
        frameSubject.send(pixelBuffer)
    }
}
