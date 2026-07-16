import XCTest
@testable import PRLifeKit

final class LifeWidgetLinksTests: XCTestCase {
    func test_contextSpecificNativeLinks() {
        XCTAssertEqual(LifeDeepLink.event(id: "event 1").absoluteString, "prlife://event?id=event%201")
        XCTAssertEqual(LifeDeepLink.task(id: "task/1").absoluteString, "prlife://task?id=task/1")
        XCTAssertEqual(LifeDeepLink.capture(context: .journal).absoluteString, "prlife://capture?context=journal")
        XCTAssertEqual(LifeDeepLink.note.absoluteString, "prlife://note")
        XCTAssertEqual(LifeDeepLink.settings.absoluteString, "prlife://settings")
    }

    func test_webRoutesPointToFocusedWorkspaceSurfaces() {
        XCTAssertEqual(LifeWebRoute.calendar(eventID: "e 1").path, "/life/month?event=e%201")
        XCTAssertEqual(LifeWebRoute.tasks(taskID: "t1").path, "/life/tasks?task=t1")
        XCTAssertEqual(LifeWebRoute.capture(entryID: "c1").path, "/life/history?entry=c1")
        XCTAssertEqual(
            LifeDeepLink.web(.tasks(taskID: "t1")).absoluteString,
            "prlife://web?path=/life/tasks?task%3Dt1"
        )
    }

    func test_upcomingWidgetKind_isStable() {
        XCTAssertEqual(LifeWidgetKind.upcoming, "PRLifeUpcoming")
    }
}
