import XCTest
@testable import PRLifeKit

final class LifeSyncStateTests: XCTestCase {
    func test_beginningSyncTracksAttemptAndPreservesLastSuccessAndPendingCount() {
        let successfulContact = Date(timeIntervalSince1970: 100)
        let attempt = Date(timeIntervalSince1970: 200)
        let initial = LifeSyncState(
            status: .offline,
            lastSuccessfulAPIContact: successfulContact,
            currentError: "old error",
            pendingCaptureCount: 3
        )

        let syncing = initial.beginningSync(at: attempt)

        XCTAssertEqual(syncing.status, .syncing)
        XCTAssertEqual(syncing.lastAttemptedSync, attempt)
        XCTAssertEqual(syncing.lastSuccessfulAPIContact, successfulContact)
        XCTAssertNil(syncing.currentError)
        XCTAssertEqual(syncing.pendingCaptureCount, 3)
    }

    func test_authenticatedResultIsTheOnlyResultThatAdvancesLastSuccessfulContact() {
        let previousSuccess = Date(timeIntervalSince1970: 100)
        let failedAttempt = Date(timeIntervalSince1970: 200)
        let successfulAttempt = Date(timeIntervalSince1970: 300)
        let initial = LifeSyncState(
            status: .synced,
            lastSuccessfulAPIContact: previousSuccess
        )

        let offline = initial.applying(.offline, attemptedAt: failedAttempt)
        XCTAssertEqual(offline.status, .offline)
        XCTAssertEqual(offline.lastAttemptedSync, failedAttempt)
        XCTAssertEqual(offline.lastSuccessfulAPIContact, previousSuccess)
        XCTAssertNotNil(offline.currentError)

        let synced = offline.applying(.authenticated, attemptedAt: successfulAttempt)
        XCTAssertEqual(synced.status, .synced)
        XCTAssertEqual(synced.lastAttemptedSync, successfulAttempt)
        XCTAssertEqual(synced.lastSuccessfulAPIContact, successfulAttempt)
        XCTAssertNil(synced.currentError)
    }

    func test_failureResultsMapToDistinctStatuses() {
        let state = LifeSyncState()

        XCTAssertEqual(state.applying(.notConfigured).status, .notConfigured)
        XCTAssertEqual(state.applying(.authenticationFailed).status, .authenticationFailed)
        XCTAssertEqual(state.applying(.offline).status, .offline)

        let failed = state.applying(.failed("server broke"))
        XCTAssertEqual(failed.status, .failed)
        XCTAssertEqual(failed.currentError, "server broke")
    }

    func test_pendingCaptureCountCannotBeNegative() {
        XCTAssertEqual(LifeSyncState(pendingCaptureCount: -2).pendingCaptureCount, 0)
        XCTAssertEqual(
            LifeSyncState(pendingCaptureCount: 2).updatingPendingCaptureCount(-1).pendingCaptureCount,
            0
        )
    }

    func test_connectivityClassificationDistinguishesExpectedFailureClasses() {
        XCTAssertEqual(
            LifeAPIConnectivity.classify(error: LifeAPIError.notConfigured),
            .notConfigured
        )
        XCTAssertEqual(
            LifeAPIConnectivity.classify(error: LifeAPIError.server(status: 401, body: "")),
            .authenticationFailed
        )
        XCTAssertEqual(
            LifeAPIConnectivity.classify(error: URLError(.notConnectedToInternet)),
            .offline
        )

        let serverFailure = LifeAPIConnectivity.classify(
            error: LifeAPIError.server(status: 500, body: "boom")
        )
        guard case .failed(let message) = serverFailure else {
            return XCTFail("expected an unclassified server failure")
        }
        XCTAssertTrue(message.contains("500"))
    }
}
