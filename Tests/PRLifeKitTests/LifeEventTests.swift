import XCTest
@testable import PRLifeKit

final class LifeEventTests: XCTestCase {
    func test_decodesCalendarRow_withSnakeCaseAndNulls() throws {
        let json = #"""
        {
          "id": "evt_1",
          "title": "Review Session",
          "start_time": "2026-06-20T14:00:00+00:00",
          "end_time": "2026-06-20T15:30:00+00:00",
          "all_day": false,
          "location": "Studio",
          "local_date": "2026-06-20"
        }
        """#.data(using: .utf8)!

        let event = try JSONDecoder().decode(LifeEvent.self, from: json)

        XCTAssertEqual(event.id, "evt_1")
        XCTAssertEqual(event.title, "Review Session")
        XCTAssertEqual(event.allDay, false)
        XCTAssertEqual(event.location, "Studio")
        XCTAssertEqual(event.localDate, "2026-06-20")
        XCTAssertNotNil(event.start)
        XCTAssertNotNil(event.end)
    }

    func test_decodesAllDayEvent_withNullTitleAndTimes() throws {
        let json = #"""
        { "id": "evt_2", "title": null, "start_time": null, "end_time": null,
          "all_day": true, "location": null, "local_date": "2026-06-20" }
        """#.data(using: .utf8)!

        let event = try JSONDecoder().decode(LifeEvent.self, from: json)

        XCTAssertNil(event.title)
        XCTAssertNil(event.start)
        XCTAssertTrue(event.allDay)
    }

    func test_parsesFractionalSecondsTimestamp() throws {
        let json = #"""
        { "id": "evt_3", "title": "Gym", "start_time": "2026-06-20T19:00:00.000Z",
          "end_time": null, "all_day": false, "location": null, "local_date": "2026-06-20" }
        """#.data(using: .utf8)!

        let event = try JSONDecoder().decode(LifeEvent.self, from: json)
        XCTAssertNotNil(event.start)
    }
}
