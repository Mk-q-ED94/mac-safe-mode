import Foundation
import AVFoundation
import CoreVideo
import CoreMedia

// MARK: - Video Recorder
//
// Maintains a rolling pre-roll buffer of CMSampleBuffers.
// When saveClip() is called, it finalises the pre-roll + records post-roll,
// then saves to ~/Movies/MacSafe/YYYY-MM-DD_HH-mm-ss.mov

final class VideoRecorder {

    // MARK: - State

    private var config: SensorConfig = .defaults
    private var ringBuffer: [CMSampleBuffer] = []
    private let ringLock = NSLock()
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var isSaving = false
    private var postRollDeadline: Date?
    private var saveURL: URL?
    private var completionHandler: ((URL?) -> Void)?

    // MARK: - Configuration

    func updateConfig(_ newConfig: SensorConfig) {
        config = newConfig
        pruneRingBuffer()
    }

    // MARK: - Append Frame to Ring Buffer

    func appendFrame(_ sampleBuffer: CMSampleBuffer) {
        guard config.videoRecordingEnabled else { return }

        ringLock.lock()
        ringBuffer.append(sampleBuffer)
        pruneRingBufferLocked()
        ringLock.unlock()

        // If currently saving post-roll, write to assetWriter
        if isSaving, let input = videoInput, input.isReadyForMoreMediaData {
            input.append(sampleBuffer)

            // Check if post-roll period is done
            if let deadline = postRollDeadline, Date() >= deadline {
                finaliseClip()
            }
        }
    }

    // MARK: - Trigger Clip Save

    /// Starts saving: flushes pre-roll buffer then records post-roll seconds.
    func saveClip(completion: @escaping (URL?) -> Void) {
        guard config.videoRecordingEnabled, !isSaving else {
            completion(nil)
            return
        }

        let url = buildOutputURL()
        do {
            assetWriter = try AVAssetWriter(url: url, fileType: .mov)
        } catch {
            AppLogger.shared.error("VideoRecorder: failed to create writer: \(error.localizedDescription)")
            completion(nil)
            return
        }

        // Infer video format from first sample buffer
        ringLock.lock()
        let buffersToWrite = ringBuffer
        ringLock.unlock()

        guard let firstBuffer = buffersToWrite.first,
              let formatDesc = CMSampleBufferGetFormatDescription(firstBuffer)
        else {
            AppLogger.shared.warning("VideoRecorder: no buffered frames to save")
            completion(nil)
            return
        }

        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDesc)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: dimensions.width,
            AVVideoHeightKey: dimensions.height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true

        guard let writer = assetWriter, writer.canAdd(input) else {
            completion(nil)
            return
        }
        writer.add(input)
        videoInput = input

        writer.startWriting()
        writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(buffersToWrite.first!))

        // Write pre-roll
        for buffer in buffersToWrite {
            if input.isReadyForMoreMediaData {
                input.append(buffer)
            }
        }

        isSaving = true
        saveURL = url
        completionHandler = completion
        postRollDeadline = Date().addingTimeInterval(config.postRollSeconds)

        AppLogger.shared.info("VideoRecorder: saving clip to \(url.lastPathComponent)")
    }

    // MARK: - Finalise

    private func finaliseClip() {
        guard isSaving, let writer = assetWriter, let input = videoInput else { return }
        isSaving = false

        input.markAsFinished()
        let url = saveURL
        let handler = completionHandler
        writer.finishWriting {
            if writer.status == .completed {
                AppLogger.shared.info("VideoRecorder: clip saved to \(url?.lastPathComponent ?? "?")")
                handler?(url)
            } else {
                AppLogger.shared.error("VideoRecorder: write failed: \(writer.error?.localizedDescription ?? "unknown")")
                handler?(nil)
            }
        }

        assetWriter = nil
        videoInput = nil
        saveURL = nil
        completionHandler = nil
        postRollDeadline = nil
    }

    // MARK: - Helpers

    private func pruneRingBuffer() {
        ringLock.lock()
        pruneRingBufferLocked()
        ringLock.unlock()
    }

    private func pruneRingBufferLocked() {
        // Keep only samples within preRollSeconds window
        let cutoff = CMTime(
            seconds: CMClockGetTime(CMClockGetHostTimeClock()).seconds - config.preRollSeconds,
            preferredTimescale: 600
        )
        ringBuffer.removeAll {
            CMSampleBufferGetPresentationTimeStamp($0) < cutoff
        }
    }

    private func buildOutputURL() -> URL {
        let moviesURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
        let folderURL = moviesURL.appendingPathComponent("MacSafe", isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = formatter.string(from: Date())
        return folderURL.appendingPathComponent("\(name).mov")
    }
}
