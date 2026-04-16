import Foundation
import Accelerate

// MARK: - Audio Utilities

enum AudioUtilities {

    // MARK: - RMS Calculation

    /// Compute root mean square of a float buffer using vDSP (Accelerate).
    static func rms(from buffer: UnsafePointer<Float>, count: Int) -> Float {
        guard count > 0 else { return 0 }
        var meanSquare: Float = 0
        vDSP_measqv(buffer, 1, &meanSquare, vDSP_Length(count))
        return sqrt(meanSquare)
    }

    // MARK: - RMS → dBFS

    /// Convert linear RMS amplitude to dBFS (decibels relative to full scale).
    static func dBFS(from rms: Float) -> Float {
        guard rms > 0 else { return -160.0 }
        return 20.0 * log10(rms)
    }

    // MARK: - dBFS Display String

    static func displayString(dBFS: Float) -> String {
        if dBFS <= -160 { return "-∞ dBFS" }
        return String(format: "%.1f dBFS", dBFS)
    }

    // MARK: - Normalize dBFS for UI (0.0 = silent, 1.0 = full scale)

    static func normalizedLevel(dBFS: Float, floor: Float = -60.0) -> Float {
        let clamped = max(floor, min(0.0, dBFS))
        return (clamped - floor) / (0.0 - floor)
    }
}
