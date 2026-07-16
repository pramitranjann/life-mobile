import XCTest
@testable import PRLifeKit

final class LifeAPIConnectivityTests: XCTestCase {
    func test_forbiddenResponse_isAuthenticationFailure() {
        XCTAssertEqual(
            LifeAPIConnectivity.classify(error: LifeAPIError.server(status: 403, body: "forbidden")),
            .authenticationFailed
        )
    }

    func test_widgetFailurePolicy_distinguishesSetupAuthAndTemporaryFailures() {
        XCTAssertEqual(
            LifeWidgetSnapshotPolicy.classify(LifeAPIError.notConfigured),
            .configurationRequired
        )
        XCTAssertEqual(
            LifeWidgetSnapshotPolicy.classify(LifeAPIError.server(status: 401, body: "")),
            .authenticationRequired
        )
        XCTAssertEqual(
            LifeWidgetSnapshotPolicy.classify(URLError(.notConnectedToInternet)),
            .temporary
        )
        XCTAssertEqual(
            LifeWidgetSnapshotPolicy.classify(LifeAPIError.server(status: 500, body: "")),
            .temporary
        )
    }

    func test_widgetFailurePolicy_onlyUsesCacheForTemporaryFailures() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-policy-\(UUID().uuidString)", isDirectory: true)
        let store = FileLifeSnapshotStore(directory: directory, fileName: "snapshot.json")
        let snapshot = LifeSnapshot(events: [], tasks: [], generatedAt: .now)
        try store.save(snapshot)

        XCTAssertEqual(
            LifeWidgetSnapshotPolicy.cachedSnapshot(after: .temporary, from: store),
            snapshot
        )
        XCTAssertNil(
            LifeWidgetSnapshotPolicy.cachedSnapshot(after: .configurationRequired, from: store)
        )
        XCTAssertNil(
            LifeWidgetSnapshotPolicy.cachedSnapshot(after: .authenticationRequired, from: store)
        )
    }
}
