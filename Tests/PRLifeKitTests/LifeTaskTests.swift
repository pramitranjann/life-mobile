import XCTest
@testable import PRLifeKit

final class LifeTaskTests: XCTestCase {
    func test_decodesTaskRow() throws {
        let json = #"""
        { "id": "t1", "title": "Finish Albers brief", "priority": "high",
          "due_local_date": "2026-06-20", "project_slug": "albers", "status": "open" }
        """#.data(using: .utf8)!

        let task = try JSONDecoder().decode(LifeTask.self, from: json)

        XCTAssertEqual(task.id, "t1")
        XCTAssertEqual(task.title, "Finish Albers brief")
        XCTAssertEqual(task.priority, .high)
        XCTAssertEqual(task.dueLocalDate, "2026-06-20")
        XCTAssertEqual(task.projectSlug, "albers")
        XCTAssertEqual(task.status, "open")
    }

    func test_unknownPriorityDefaultsToMedium() throws {
        let json = #"""
        { "id": "t2", "title": "x", "priority": "urgent",
          "due_local_date": null, "project_slug": null, "status": "open" }
        """#.data(using: .utf8)!
        let task = try JSONDecoder().decode(LifeTask.self, from: json)
        XCTAssertEqual(task.priority, .medium)
        XCTAssertNil(task.dueLocalDate)
    }

    func test_isDueOn_matchesLocalDate() {
        let task = LifeTask(id: "t3", title: "y", priority: .low,
                            dueLocalDate: "2026-06-20", projectSlug: nil, status: "open")
        XCTAssertTrue(task.isDue(on: "2026-06-20"))
        XCTAssertFalse(task.isDue(on: "2026-06-21"))
    }
}
