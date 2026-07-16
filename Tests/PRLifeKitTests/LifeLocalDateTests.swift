import XCTest
@testable import PRLifeKit

final class LifeLocalDateTests: XCTestCase {
    func test_current_usesPassedTimeZone() {
        let now = Date(timeIntervalSince1970: 1_750_000_000) // 2025-06-15 15:06:40 UTC

        XCTAssertEqual(
            LifeLocalDate.current(
                now: now,
                timeZone: TimeZone(secondsFromGMT: 0)!
            ),
            "2025-06-15"
        )

        XCTAssertEqual(
            LifeLocalDate.current(
                now: now,
                timeZone: TimeZone(secondsFromGMT: 8 * 3600)!
            ),
            "2025-06-15"
        )

        XCTAssertEqual(
            LifeLocalDate.current(
                now: now,
                timeZone: TimeZone(secondsFromGMT: -8 * 3600)!
            ),
            "2025-06-15"
        )
    }
}
