import XCTest
@testable import PRLifeKit

final class PRLifeTokensTests: XCTestCase {
    func test_accentHex() { XCTAssertEqual(PRLifeTokens.Color.accent, "FF3120") }
    func test_backgroundHex() { XCTAssertEqual(PRLifeTokens.Color.background, "0A0A0A") }
}
