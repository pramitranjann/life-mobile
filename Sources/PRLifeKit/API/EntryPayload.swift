import Foundation

public struct EntryPayload: Codable, Equatable, Sendable {
    public let content: String
    public let source: String        // always "voice" for V1
    public let projectSlug: String?

    public init(content: String, source: String = "voice", projectSlug: String?) {
        self.content = content
        self.source = source
        self.projectSlug = projectSlug
    }
}

