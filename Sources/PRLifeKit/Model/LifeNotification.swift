import Foundation

public struct LifeNotification: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: String
    public let title: String
    public let body: String
    public let url: URL?
    public let metadata: [String: String]
    public let createdAt: Date
    public let readAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, kind, title, body, url, metadata
        case createdAt = "created_at"
        case readAt = "read_at"
    }

    public init(
        id: String,
        kind: String,
        title: String,
        body: String,
        url: URL?,
        metadata: [String: String],
        createdAt: Date,
        readAt: Date?
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.url = url
        self.metadata = metadata
        self.createdAt = createdAt
        self.readAt = readAt
    }

    /// Time Sensitive is reserved for alerts with a server-provided destination time
    /// that is actually close. A newly-created notification is not urgent by itself.
    public func isGenuinelyImminent(
        relativeTo now: Date,
        maximumLeadTime: TimeInterval = 60 * 60
    ) -> Bool {
        let timestampKeys = [
            "eventAt", "event_at", "startsAt", "starts_at",
            "deadline", "deadline_at", "dueAt", "due_at", "fireAt", "fire_at"
        ]
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]

        for key in timestampKeys {
            guard let rawValue = metadata[key],
                  let destinationTime = parser.date(from: rawValue) ?? fallback.date(from: rawValue) else {
                continue
            }
            let interval = destinationTime.timeIntervalSince(now)
            return interval >= -5 * 60 && interval <= maximumLeadTime
        }
        return false
    }
}
