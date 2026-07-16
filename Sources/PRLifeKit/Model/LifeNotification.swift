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
}
