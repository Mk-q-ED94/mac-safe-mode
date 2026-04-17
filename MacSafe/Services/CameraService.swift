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
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionWasInterrupted, object: session)
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionInterruptionEnded, object: session)
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

    // MARK: - Session Interruption Handling
    //
    // On macOS 14+ (and sometimes 13), the OS can interrupt the AVCaptureSession
    // when the screen locks or the display sleeps as a privacy measure.
    // We register for these notifications so we can log the event and automatically
    // restart the session when the camera becomes available again (e.g. screen unlocks).

    private func registerInterruptionObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWasInterrupted(_:)),
            name: .AVCaptureSessionWasInterrupted,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded(_:)),
            name: .AVCaptureSessionInterruptionEnded,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRuntimeError(_:)),
            name: .AVCaptureSessionRuntimeError,
            object: session
        )
    }

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        AppLogger.shared.info("CameraService: session interrupted — camera unavailable (e.g. screen locked or display sleeping)")
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        AppLogger.shared.info("CameraService: interruption ended — restarting session")
        captureQueue.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.session.startRunning()
        }
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        AppLogger.shared.error("CameraService: runtime error \(error.code.rawValue) — \(error.localizedDescription)")
        // Attempt recovery for transient errors (e.g. media services reset).
        // AVError.Code does not expose a mediaServicesWereReset member on macOS,
        // so we attempt restart unconditionally for any runtime error.
        captureQueue.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.session.startRunning()
        }
    }

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

        // Register for interruption/error notifications (must be after session is configured)
        registerInterruptionObservers()

        // Set lowest supported fps to minimize resource usage
        try device.lockForConfiguration()
        let supportedRanges = device.activeFormat.videoSupportedFrameRateRanges
        if let minRange = supportedRanges.min(by: { $0.minFrameRate < $1.minFrameRate }) {
            let duration = CMTime(value: 1, timescale: CMTimeScale(minRange.minFrameRate))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
        }
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
