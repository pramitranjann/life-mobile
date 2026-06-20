import Foundation

/// The single cached payload both the app and widget read.
public struct LifeSnapshot: Codable, Equatable, Sendable {
    public let events: [LifeEvent]
    public let tasks: [LifeTask]
    public let lastSync: Date

    public init(events: [LifeEvent], tasks: [LifeTask], lastSync: Date) {
        self.events = events; self.tasks = tasks; self.lastSync = lastSync
    }
}
