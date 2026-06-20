import Foundation

public enum LifeTaskPriority: String, Codable, Sendable, CaseIterable {
    case high, medium, low
}

/// A task read from `GET /api/life/tasks`.
public struct LifeTask: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let priority: LifeTaskPriority
    public let dueLocalDate: String?
    public let projectSlug: String?
    public let status: String

    enum CodingKeys: String, CodingKey {
        case id, title, priority, status
        case dueLocalDate = "due_local_date"
        case projectSlug = "project_slug"
    }

    public init(id: String, title: String, priority: LifeTaskPriority,
                dueLocalDate: String?, projectSlug: String?, status: String) {
        self.id = id; self.title = title; self.priority = priority
        self.dueLocalDate = dueLocalDate; self.projectSlug = projectSlug; self.status = status
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        let raw = try c.decodeIfPresent(String.self, forKey: .priority)
        priority = raw.flatMap(LifeTaskPriority.init(rawValue:)) ?? .medium
        dueLocalDate = try c.decodeIfPresent(String.self, forKey: .dueLocalDate)
        projectSlug = try c.decodeIfPresent(String.self, forKey: .projectSlug)
        status = try c.decode(String.self, forKey: .status)
    }

    public func isDue(on localDate: String) -> Bool { dueLocalDate == localDate }
}
