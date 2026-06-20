import Foundation

/// Pure selection helpers shared by every widget family.
public enum LifeDashboard {
    /// Upcoming events (start in the future), sorted ascending, capped at `limit`.
    public static func nextEvents(_ events: [LifeEvent], limit: Int, now: Date = Date()) -> [LifeEvent] {
        events
            .filter { ($0.start ?? .distantPast) >= now }
            .sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }

    /// Tasks ordered high->low priority (stable within a priority), capped at `limit`.
    public static func topTasks(_ tasks: [LifeTask], limit: Int) -> [LifeTask] {
        func rank(_ p: LifeTaskPriority) -> Int { p == .high ? 0 : (p == .medium ? 1 : 2) }
        return tasks
            .enumerated()
            .sorted { (rank($0.element.priority), $0.offset) < (rank($1.element.priority), $1.offset) }
            .map(\.element)
            .prefix(limit)
            .map { $0 }
    }
}
