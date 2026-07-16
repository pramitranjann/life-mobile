import Foundation

/// The single cached payload both the app and widget read.
public struct LifeSnapshot: Codable, Equatable, Sendable {
    public let events: [LifeEvent]
    public let tasks: [LifeTask]
    /// When the API successfully produced this exact event/task payload.
    public let generatedAt: Date
    public let localDate: String?

    public init(events: [LifeEvent], tasks: [LifeTask], generatedAt: Date, localDate: String? = nil) {
        self.events = events
        self.tasks = tasks
        self.generatedAt = generatedAt
        self.localDate = localDate
    }

    /// Compatibility spelling retained for the macOS sync surface while callers
    /// migrate to the more precise cache-generation terminology.
    public var lastSync: Date { generatedAt }

    public init(events: [LifeEvent], tasks: [LifeTask], lastSync: Date, localDate: String? = nil) {
        self.init(events: events, tasks: tasks, generatedAt: lastSync, localDate: localDate)
    }

    private enum CodingKeys: String, CodingKey {
        case events, tasks, generatedAt, lastSync, localDate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        events = try container.decode([LifeEvent].self, forKey: .events)
        tasks = try container.decode([LifeTask].self, forKey: .tasks)
        if let date = try container.decodeIfPresent(Date.self, forKey: .generatedAt) {
            generatedAt = date
        } else {
            generatedAt = try container.decode(Date.self, forKey: .lastSync)
        }
        localDate = try container.decodeIfPresent(String.self, forKey: .localDate)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(events, forKey: .events)
        try container.encode(tasks, forKey: .tasks)
        try container.encode(generatedAt, forKey: .generatedAt)
        // Older installed app/widget versions only understand `lastSync`.
        try container.encode(generatedAt, forKey: .lastSync)
        try container.encodeIfPresent(localDate, forKey: .localDate)
    }
}

public struct LifeSnapshotAge: Equatable, Sendable {
    public let generatedAt: Date
    public let now: Date
    public let staleAfter: TimeInterval

    public init(generatedAt: Date, now: Date = Date(), staleAfter: TimeInterval = 2 * 60 * 60) {
        self.generatedAt = generatedAt
        self.now = now
        self.staleAfter = staleAfter
    }

    public var age: TimeInterval { max(0, now.timeIntervalSince(generatedAt)) }
    public var isStale: Bool { age >= staleAfter }

    public var label: String {
        let prefix = isStale ? "STALE · " : ""
        if age < 60 { return "\(prefix)UPDATED JUST NOW" }
        if age < 60 * 60 { return "\(prefix)UPDATED \(Int(age / 60))M AGO" }
        if age < 24 * 60 * 60 { return "\(prefix)UPDATED \(Int(age / (60 * 60)))H AGO" }
        return "\(prefix)UPDATED \(Int(age / (24 * 60 * 60)))D AGO"
    }
}
