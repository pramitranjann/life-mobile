import XCTest
@testable import PRLifeKit

final class CaptureContextTests: XCTestCase {
    func test_projectSlug_mapsKnownContexts() {
        XCTAssertEqual(CaptureContext.work.projectSlug, "work")
        XCTAssertEqual(CaptureContext.journal.projectSlug, "journal")
        XCTAssertEqual(CaptureContext.ideas.projectSlug, "ideas")
    }

    func test_quick_hasNoProjectSlug() {
        XCTAssertNil(CaptureContext.quick.projectSlug)
    }

    func test_status_isTerminal() {
        XCTAssertTrue(CaptureStatus.done.isTerminal)
        XCTAssertTrue(CaptureStatus.failed.isTerminal)
        XCTAssertFalse(CaptureStatus.recording.isTerminal)
        XCTAssertFalse(CaptureStatus.processing.isTerminal)
    }
}
