import XCTest
@testable import PRLifeKit

final class UploadGateTests: XCTestCase {
    func test_wifiOnly_blocksOnCellular() {
        let gate = UploadGate(reachability: FakeReachability(.cellular), wifiOnly: true)
        XCTAssertFalse(gate.canUploadNow())
    }
    func test_wifiOnly_allowsOnWifi() {
        let gate = UploadGate(reachability: FakeReachability(.wifi), wifiOnly: true)
        XCTAssertTrue(gate.canUploadNow())
    }
    func test_wifiOff_allowsOnCellular() {
        let gate = UploadGate(reachability: FakeReachability(.cellular), wifiOnly: false)
        XCTAssertTrue(gate.canUploadNow())
    }
    func test_offline_blocksAlways() {
        let gate = UploadGate(reachability: FakeReachability(.offline), wifiOnly: false)
        XCTAssertFalse(gate.canUploadNow())
    }
}
