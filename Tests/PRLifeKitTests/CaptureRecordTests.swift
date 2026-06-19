import XCTest
@testable import PRLifeKit

final class CaptureRecordTests: XCTestCase {
    func test_init_defaults() {
        let r = CaptureRecord(context: .work)
        XCTAssertEqual(r.status, .recording)
        XCTAssertEqual(r.context, .work)
        XCTAssertNil(r.transcript)
        XCTAssertNil(r.serverEntryId)
        XCTAssertEqual(r.retryCount, 0)
    }

    func test_action_equatable() {
        XCTAssertEqual(PRLifeAction.startCapture(context: .ideas),
                       PRLifeAction.startCapture(context: .ideas))
        XCTAssertNotEqual(PRLifeAction.startCapture(context: .ideas),
                          PRLifeAction.stopCapture)
    }
}
