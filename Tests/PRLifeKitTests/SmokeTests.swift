import XCTest
@testable import PRLifeKit

final class SmokeTests: XCTestCase {
    func test_version_isSet() {
        XCTAssertEqual(PRLifeKit.version, "0.1.0")
    }
}
