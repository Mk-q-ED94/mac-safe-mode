import Foundation
import Vision
import AppKit
import Combine

// MARK: - Whitelist Entry

struct FaceWhitelistEntry: Identifiable, Codable {
    let id: UUID
    var name: String
    var thumbnailData: Data       // JPEG of face crop, for display
    var featurePrintData: Data    // NSKeyedArchiver-encoded VNFeaturePrintObservation

    var thumbnail: NSImage? { NSImage(data: thumbnailData) }
}

// MARK: - Face Whitelist Manager

@MainActor
final class FaceWhitelistManager: ObservableObject {

    static let shared = FaceWhitelistManager()

    @Published private(set) var entries: [FaceWhitelistEntry] = []

    /// Similarity threshold. VNFeaturePrintObservation distances are 0–1;
    /// lower = stricter. 0.55 gives reasonable accuracy for casual use.
    static let matchThreshold: Float = 0.55

    private let saveURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacSafe", isDirectory: true)
        return dir.appendingPathComponent("whitelist.json")
    }()

    private init() { load() }

    // MARK: - CRUD

    func removeEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
        AppLogger.shared.info("FaceWhitelist: removed entry \(id)")
    }

    /// Enroll a face from an NSImage. Returns a localized error string on failure, nil on success.
    func addEntry(name: String, image: NSImage) async -> String? {
        // Extract CGImage on main thread — NSImage is not thread-safe
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return "Could not decode the selected image."
        }
        let indexHint = entries.count
        let label = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Person \(indexHint + 1)" : name

        let result: Result<FaceWhitelistEntry, String> = await Task.detached(priority: .userInitiated) {
            Self.enrollSync(cgImage: cgImage, name: label)
        }.value

        switch result {
        case .success(let entry):
            entries.append(entry)
            save()
            AppLogger.shared.info("FaceWhitelist: enrolled '\(entry.name)'")
            return nil
        case .failure(let msg):
            return msg
        }
    }

    // MARK: - Recognition (static — called from background threads in FaceDetector)

    /// Checks synchronously whether the face at boundingBox in pixelBuffer matches any entry.
    /// Safe to call from any thread; caller provides the entries snapshot.
    static func isWhitelisted(
        pixelBuffer: CVPixelBuffer,
        boundingBox: CGRect,
        entries: [FaceWhitelistEntry]
    ) -> Bool {
        guard !entries.isEmpty else { return false }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = ctx.createCGImage(ciImage, from: ciImage.extent) else { return false }

        let crop = cropFace(from: cgImage, normalizedBoundingBox: boundingBox)
        guard let current = featurePrint(for: crop) else { return false }

        for entry in entries {
            guard let stored = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: VNFeaturePrintObservation.self, from: entry.featurePrintData
            ) else { continue }
            var dist: Float = 1.0
            guard (try? stored.computeDistance(&dist, to: current)) != nil else { continue }
            AppLogger.shared.info("FaceWhitelist: '\(entry.name)' dist=\(String(format: "%.3f", dist))")
            if dist < matchThreshold {
                AppLogger.shared.info("FaceWhitelist: matched '\(entry.name)' — suppressing alert")
                return true
            }
        }
        return false
    }

    // MARK: - Private: Enrollment (runs on background thread)

    private static func enrollSync(cgImage: CGImage, name: String) -> Result<FaceWhitelistEntry, String> {
        // 1. Detect faces
        let faceReq = VNDetectFaceRectanglesRequest()
        do { try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([faceReq]) }
        catch { return .failure("Face detection failed: \(error.localizedDescription)") }

        let faces = (faceReq.results as? [VNFaceObservation]) ?? []
        if faces.isEmpty { return .failure("No face found — use a clear, front-facing photo.") }
        if faces.count > 1 { return .failure("Multiple faces detected — use a photo with one person.") }

        // 2. Crop face
        let crop = cropFace(from: cgImage, normalizedBoundingBox: faces[0].boundingBox)

        // 3. Feature print
        guard let fp = featurePrint(for: crop) else {
            return .failure("Could not compute face features.")
        }
        guard let fpData = try? NSKeyedArchiver.archivedData(withRootObject: fp, requiringSecureCoding: true) else {
            return .failure("Could not serialize face features.")
        }

        // 4. Thumbnail (JPEG via CGImageDestination — thread-safe)
        guard let thumbData = jpegData(from: crop) else {
            return .failure("Could not create thumbnail.")
        }

        return .success(FaceWhitelistEntry(id: UUID(), name: name, thumbnailData: thumbData, featurePrintData: fpData))
    }

    // MARK: - Private: Crop Helper

    /// Crop face region from a CGImage using Vision's normalized bounding box (origin bottom-left).
    private static func cropFace(from cgImage: CGImage, normalizedBoundingBox bb: CGRect) -> CGImage {
        let w = CGFloat(cgImage.width), h = CGFloat(cgImage.height)
        // Vision: bottom-left origin → CGImage: top-left origin
        let x = bb.minX * w
        let y = (1.0 - bb.maxY) * h
        let fw = bb.width * w, fh = bb.height * h
        // 25% padding for better recognition stability
        let padX = fw * 0.25, padY = fh * 0.25
        let rect = CGRect(x: max(0, x - padX), y: max(0, y - padY),
                          width: min(w, fw + padX * 2), height: min(h, fh + padY * 2))
            .intersection(CGRect(origin: .zero, size: CGSize(width: w, height: h)))
        return cgImage.cropping(to: rect) ?? cgImage
    }

    // MARK: - Private: Feature Print

    private static func featurePrint(for cgImage: CGImage) -> VNFeaturePrintObservation? {
        let req = VNGenerateImageFeaturePrintRequest()
        guard (try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([req])) != nil else { return nil }
        return req.results?.first as? VNFeaturePrintObservation
    }

    // MARK: - Private: JPEG encoding (thread-safe, no NSImage needed)

    private static func jpegData(from cgImage: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, "public.jpeg" as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    // MARK: - Persistence

    private func save() {
        do {
            let dir = saveURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: saveURL)
        } catch {
            AppLogger.shared.error("FaceWhitelist save: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode([FaceWhitelistEntry].self, from: data) else { return }
        entries = decoded
        AppLogger.shared.info("FaceWhitelist: loaded \(decoded.count) entry(s)")
    }
}
