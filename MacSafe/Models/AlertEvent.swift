import Foundation

// MARK: - Alert Event

struct AlertEvent: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let type: AlertType
    let score: Float        // Sensor score at time of alert (0.0 - 1.0 or dBFS for audio)
    var videoURL: URL?      // Path to saved video clip, if any

    init(type: AlertType, score: Float, videoURL: URL? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.type = type
        self.score = score
        self.videoURL = videoURL
    }

    // MARK: - Codable support for URL

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, type, score, videoURLString
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        type = try container.decode(AlertType.self, forKey: .type)
        score = try container.decode(Float.self, forKey: .score)
        if let urlString = try container.decodeIfPresent(String.self, forKey: .videoURLString) {
            videoURL = URL(string: urlString)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(type, forKey: .type)
        try container.encode(score, forKey: .score)
        try container.encodeIfPresent(videoURL?.absoluteString, forKey: .videoURLString)
    }
}

// MARK: - Alert History Store

class AlertHistory: ObservableObject {
    static let shared = AlertHistory()

    @Published private(set) var events: [AlertEvent] = []

    private static let maxEvents = 100
    private static let userDefaultsKey = "alertHistory"

    init() {
        load()
    }

    func append(_ event: AlertEvent) {
        events.insert(event, at: 0)
        if events.count > Self.maxEvents {
            events = Array(events.prefix(Self.maxEvents))
        }
        save()
    }

    func clear() {
        events = []
        UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey),
            let decoded = try? JSONDecoder().decode([AlertEvent].self, from: data)
        else { return }
        events = decoded
    }
}
