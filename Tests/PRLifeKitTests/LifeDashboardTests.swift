import XCTest
@testable import PRLifeKit

final class LifeDashboardTests: XCTestCase {
    private func ev(_ id: String, minsFromNow: Int, now: Date) -> LifeEvent {
        let iso = ISO8601DateFormatter().string(from: now.addingTimeInterval(Double(minsFromNow) * 60))
        return LifeEvent(id: id, title: "E\(id)", startTime: iso, endTime: nil,
                         allDay: false, location: nil, localDate: "2026-06-20")
    }
    private func task(_ id: String, _ p: LifeTaskPriority) -> LifeTask {
        LifeTask(id: id, title: "T\(id)", priority: p, dueLocalDate: nil, projectSlug: nil, status: "open")
    }

    func test_nextEvents_dropsPastAndSortsByStart() {
        let now = Date()
        let events = [ev("a", minsFromNow: 30, now: now),
                      ev("b", minsFromNow: -10, now: now),
                      ev("c", minsFromNow: 5, now: now)]
        XCTAssertEqual(LifeDashboard.nextEvents(events, limit: 5, now: now).map(\.id), ["c", "a"])
    }

    func test_nextEvents_respectsLimit() {
        let now = Date()
        let events = [ev("a", minsFromNow: 5, now: now),
                      ev("b", minsFromNow: 10, now: now),
                      ev("c", minsFromNow: 15, now: now)]
        XCTAssertEqual(LifeDashboard.nextEvents(events, limit: 2, now: now).map(\.id), ["a", "b"])
    }

    func test_topTasks_ordersByPriorityThenLimit() {
        let tasks = [task("a", .low), task("b", .high), task("c", .medium)]
        XCTAssertEqual(LifeDashboard.topTasks(tasks, limit: 2).map(\.id), ["b", "c"])
    }
}
