import Foundation
import CoreImage
import AppKit
import CoreVideo

// MARK: - Image Utilities

enum ImageUtilities {

    // MARK: - CVPixelBuffer → CIImage

    static func ciImage(from pixelBuffer: CVPixelBuffer) -> CIImage {
        CIImage(cvPixelBuffer: pixelBuffer)
    }

    // MARK: - CIImage → NSImage

    static func nsImage(from ciImage: CIImage, context: CIContext) -> NSImage? {
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: ciImage.extent.size)
    }

    // MARK: - CVPixelBuffer → NSImage (thumbnail)

    static func thumbnail(from pixelBuffer: CVPixelBuffer,
                          maxDimension: CGFloat = 320,
                          context: CIContext) -> NSImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ciImage.extent
        let scale = min(maxDimension / extent.width, maxDimension / extent.height)
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return nsImage(from: scaledImage, context: context)
    }

    // MARK: - NSImage → PNG Data

    static func pngData(from nsImage: NSImage) -> Data? {
        guard let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Shared CIContext (GPU-backed, reusable)

    static let sharedContext: CIContext = {
        CIContext(options: [.useSoftwareRenderer: false, .highQualityDownsample: false])
    }()
}
