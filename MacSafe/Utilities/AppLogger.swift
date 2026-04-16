import Foundation
import os.log

// MARK: - App Logger

final class AppLogger {
    static let shared = AppLogger()

    private let logger = Logger(subsystem: "com.macsafe.app", category: "MacSafe")

    private init() {}

    func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
