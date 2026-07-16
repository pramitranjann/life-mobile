import Foundation

public struct EntryPayload: Codable, Equatable, Sendable {
    public let content: String
    public let source: String
    public let projectSlug: String?

    public init(content: String, source: String = "voice", projectSlug: String?) {
        self.content = content
        self.source = source
        self.projectSlug = projectSlug
    }
}

public struct TaskPayload: Codable, Equatable, Sendable {
    public let title: String
    public let details: String?
    public let projectSlug: String?
    public let dueLocalDate: String?
    public let priority: String?
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case title, details, priority, status
        case projectSlug = "project_slug"
        case dueLocalDate = "due_local_date"
    }

    public init(title: String,
                details: String? = nil,
                projectSlug: String? = nil,
                dueLocalDate: String? = nil,
                priority: String? = nil,
                status: String? = nil) {
        self.title = title
        self.details = details
        self.projectSlug = projectSlug
        self.dueLocalDate = dueLocalDate
        self.priority = priority
        self.status = status
    }
}

/// PATCH payload for a task. Unlike `TaskPayload`, every field is optional so
/// completing a task never overwrites its title or scheduling metadata.
public struct TaskUpdatePayload: Codable, Equatable, Sendable {
    public let title: String?
    public let projectSlug: String?
    public let dueLocalDate: String?
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case title, status
        case projectSlug = "project_slug"
        case dueLocalDate = "due_local_date"
    }

    public init(title: String? = nil,
                projectSlug: String? = nil,
                dueLocalDate: String? = nil,
                status: String? = nil) {
        self.title = title
        self.projectSlug = projectSlug
        self.dueLocalDate = dueLocalDate
        self.status = status
    }
}
