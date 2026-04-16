import Foundation

// MARK: - Pushover Service

/// Sends push notifications to the user's mobile device via the Pushover API.
/// Docs: https://pushover.net/api
struct PushoverService {

    // MARK: - API

    private static let endpoint = URL(string: "https://api.pushover.net/1/messages.json")!

    // MARK: - Send Notification

    static func send(
        title: String,
        message: String,
        userKey: String,
        apiToken: String,
        priority: Priority = .normal,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard !userKey.isEmpty, !apiToken.isEmpty else {
            AppLogger.shared.warning("PushoverService: missing credentials, skipping push")
            completion?(false)
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [String: String] = [
            "token": apiToken,
            "user": userKey,
            "title": title,
            "message": message,
            "priority": String(priority.rawValue),
            "sound": "siren"
        ]
        request.httpBody = params
            .map { "\($0.key)=\($0.value.urlEncoded)" }
            .joined(separator: "&")
            .data(using: .utf8)

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                AppLogger.shared.error("PushoverService: \(error.localizedDescription)")
                completion?(false)
                return
            }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let success = statusCode == 200
            AppLogger.shared.info("PushoverService: sent (HTTP \(statusCode))")
            completion?(success)
        }.resume()
    }

    // MARK: - Priority

    enum Priority: Int {
        case lowest = -2
        case low = -1
        case normal = 0
        case high = 1
        case emergency = 2
    }
}

// MARK: - String URL Encoding Helper

private extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
