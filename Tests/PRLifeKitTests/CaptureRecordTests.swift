import XCTest
@testable import PRLifeKit

final class CaptureRecordTests: XCTestCase {
    func test_init_defaults() {
        let r = CaptureRecord(context: .work)
        XCTAssertEqual(r.status, .recording)
        XCTAssertEqual(r.context, .work)
        XCTAssertEqual(r.mode, .voice)
        XCTAssertEqual(r.projectSlug, "work")
        XCTAssertNil(r.transcript)
        XCTAssertNil(r.serverEntryId)
        XCTAssertEqual(r.retryCount, 0)
        XCTAssertNil(r.inputRoute)
        XCTAssertNil(r.recoveryReason)
        XCTAssertFalse(r.canResume)
        XCTAssertFalse(r.canRetry)
        XCTAssertFalse(r.canSave)
        XCTAssertTrue(r.canDiscard)
    }

    func test_textCaptureCapabilities_areDurableWithoutAudio() {
        let note = CaptureRecord(
            context: .quick,
            mode: .note,
            projectSlug: "studio",
            transcript: "Review this",
            status: .failed
        )

        XCTAssertEqual(note.mode.badgeLabel, "NOTE_")
        XCTAssertEqual(note.projectSlug, "studio")
        XCTAssertTrue(note.canRetry)
        XCTAssertTrue(note.canSave)
    }

    func test_recoveryState_exposesResumeAndRetryCapabilities() {
        let route = AudioInputRoute(identifier: "airpods", name: "AirPods Pro", portType: "BluetoothHFP")
        let interrupted = CaptureRecord(
            context: .work,
            audioFileName: "partial.m4a",
            status: .failed,
            inputRoute: route,
            recoveryReason: .inputRouteLost
        )

        XCTAssertEqual(interrupted.inputRoute, route)
        XCTAssertEqual(interrupted.recoveryReason, .inputRouteLost)
        XCTAssertTrue(interrupted.canResume)
        XCTAssertTrue(interrupted.canRetry)
        XCTAssertTrue(CaptureRecoveryReason.inputRouteLost.message.contains("saved"))
    }

    func test_action_equatable() {
        XCTAssertEqual(PRLifeAction.startCapture(context: .ideas),
                       PRLifeAction.startCapture(context: .ideas))
        XCTAssertNotEqual(PRLifeAction.startCapture(context: .ideas),
                          PRLifeAction.stopCapture)
    }
}
