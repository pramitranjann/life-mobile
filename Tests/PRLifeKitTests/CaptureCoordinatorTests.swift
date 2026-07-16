import XCTest
@testable import PRLifeKit

@MainActor
final class CaptureCoordinatorTests: XCTestCase {
    private func makeSUT() -> (CaptureCoordinator, InMemoryCaptureStore, FakeRecorder, FakeTranscriber, LifeAPIClient) {
        let store = InMemoryCaptureStore()
        let recorder = FakeRecorder()
        let transcriber = FakeTranscriber()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = LifeAPIClient(baseURL: URL(string: "https://e.com")!, token: "t",
                                   session: URLSession(configuration: config))
        let sut = CaptureCoordinator(store: store, recorder: recorder,
                                     transcriber: transcriber, api: client,
                                     gate: UploadGate(reachability: FakeReachability(.wifi), wifiOnly: false))
        return (sut, store, recorder, transcriber, client)
    }

    func test_startThenStop_runsFullPipelineToDone() async {
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data(#"{"entry":{"id":"srv1"}}"#.utf8))
        }
        let (sut, store, _, _, _) = makeSUT()
        await sut.handle(.startCapture(context: .work))
        XCTAssertEqual(store.all().first?.status, .recording)

        await sut.handle(.stopCapture)
        let rec = store.all().first
        XCTAssertEqual(rec?.status, .done)
        XCTAssertEqual(rec?.transcript, "hello")
        XCTAssertEqual(rec?.serverEntryId, "srv1")
        XCTAssertEqual(rec?.duration, 12)
        XCTAssertEqual(rec?.inputRoute?.name, "iPhone Microphone")
        XCTAssertNil(rec?.recoveryReason)
    }

    func test_stopWhenNotRecording_isIgnored() async {
        let (sut, store, _, _, _) = makeSUT()
        await sut.handle(.stopCapture)
        XCTAssertTrue(store.all().isEmpty)
    }

    func test_startWhenAlreadyRecording_isIgnored() async {
        let (sut, store, _, _, _) = makeSUT()
        await sut.handle(.startCapture(context: .work))
        await sut.handle(.startCapture(context: .ideas))
        XCTAssertEqual(store.all().count, 1)
        XCTAssertEqual(store.all().first?.context, .work)
    }

    func test_uploadFailure_marksFailedAndKeepsTranscript() async {
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }
        let (sut, store, _, _, _) = makeSUT()
        await sut.handle(.startCapture(context: .quick))
        await sut.handle(.stopCapture)
        let rec = store.all().first
        XCTAssertEqual(rec?.status, .failed)
        XCTAssertEqual(rec?.transcript, "hello")     // transcript preserved for retry
        XCTAssertEqual(rec?.retryCount, 1)
    }

    func test_emptyTranscript_marksFailed() async {
        let (sut, store, _, transcriber, _) = makeSUT()
        transcriber.result = .failure(.emptyTranscript)
        await sut.handle(.startCapture(context: .quick))
        await sut.handle(.stopCapture)
        XCTAssertEqual(store.all().first?.status, .failed)
    }

    func test_recorderStartThrows_marksFailedAndStaysIdle() async {
        let (sut, store, recorder, _, _) = makeSUT()
        recorder.startError = .permissionDenied
        await sut.handle(.startCapture(context: .work))
        let rec = store.all().first
        XCTAssertEqual(rec?.status, .failed)
        XCTAssertFalse(sut.isRecording)               // active slot released
        // a subsequent start should work (not blocked by a leaked activeID)
        recorder.startError = nil
        await sut.handle(.startCapture(context: .ideas))
        XCTAssertTrue(sut.isRecording)
        XCTAssertEqual(store.all().count, 2)
    }

    func test_uploadGatedOffline_marksFailedAndKeepsTranscript() async {
        // Build a SUT whose gate blocks (offline).
        let store = InMemoryCaptureStore()
        let recorder = FakeRecorder()
        let transcriber = FakeTranscriber()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = LifeAPIClient(baseURL: URL(string: "https://e.com")!, token: "t",
                                   session: URLSession(configuration: config))
        let sut = CaptureCoordinator(store: store, recorder: recorder,
                                     transcriber: transcriber, api: client,
                                     gate: UploadGate(reachability: FakeReachability(.offline), wifiOnly: false))
        await sut.handle(.startCapture(context: .quick))
        await sut.handle(.stopCapture)
        let rec = store.all().first
        XCTAssertEqual(rec?.status, .failed)
        XCTAssertEqual(rec?.transcript, "hello")   // transcript preserved despite gate block
    }

    func test_routeLoss_finishesPartialCaptureAndRunsNormalPipeline() async {
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data(#"{"entry":{"id":"partial1"}}"#.utf8))
        }
        let (sut, store, recorder, _, _) = makeSUT()
        recorder.selectedInputRoute = .init(
            identifier: "airpods-pro",
            name: "AirPods Pro 3",
            portType: "BluetoothHFP"
        )

        await sut.handle(.startCapture(context: .work))
        let id = store.all().first!.id
        var events: [CaptureCoordinatorEvent] = []
        sut.eventHandler = { events.append($0) }
        await sut.handleRecordingTermination(.inputRouteLost)

        let record = store.all().first
        XCTAssertFalse(sut.isRecording)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.stopCallCount, 1)
        XCTAssertEqual(record?.status, .done)
        XCTAssertEqual(record?.duration, 12)
        XCTAssertEqual(record?.transcript, "hello")
        XCTAssertEqual(record?.serverEntryId, "partial1")
        XCTAssertEqual(record?.inputRoute?.name, "AirPods Pro 3")
        XCTAssertEqual(record?.recoveryReason, .inputRouteLost)
        XCTAssertTrue(record?.canResume == true)
        XCTAssertEqual(events, [
            .recordingFinalized(id: id, recoveryReason: .inputRouteLost),
            .completed(id: id),
        ])
    }

    func test_interruptionWithTranscriptionFailure_preservesAudioAsRetryableAndDoesNotStick() async {
        let (sut, store, recorder, transcriber, _) = makeSUT()
        transcriber.result = .failure(.recognizerUnavailable)

        await sut.handle(.startCapture(context: .quick))
        let id = store.all().first!.id
        var events: [CaptureCoordinatorEvent] = []
        sut.eventHandler = { events.append($0) }
        await sut.handleRecordingTermination(.audioInterrupted)

        let record = store.all().first
        XCTAssertFalse(sut.isRecording)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(record?.status, .failed)
        XCTAssertNotEqual(record?.status, .recording)
        XCTAssertNotEqual(record?.status, .processing)
        XCTAssertEqual(record?.audioFileName, "capture-1.m4a")
        XCTAssertEqual(record?.recoveryReason, .audioInterrupted)
        XCTAssertTrue(record?.canResume == true)
        XCTAssertTrue(record?.canRetry == true)
        XCTAssertEqual(events.first, .recordingFinalized(id: id, recoveryReason: .audioInterrupted))
        guard case .failed(let failedID, _) = events.last else {
            return XCTFail("Expected terminal failure event")
        }
        XCTAssertEqual(failedID, id)
    }

    func test_duplicateUnexpectedTermination_isIgnoredAfterFirstFinalization() async {
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data(#"{"entry":{"id":"partial2"}}"#.utf8))
        }
        let (sut, store, recorder, _, _) = makeSUT()

        await sut.handle(.startCapture(context: .ideas))
        await sut.handleRecordingTermination(.audioInterrupted)
        await sut.handleRecordingTermination(.inputRouteLost)

        XCTAssertEqual(recorder.stopCallCount, 1)
        XCTAssertEqual(store.all().first?.status, .done)
        XCTAssertEqual(store.all().first?.recoveryReason, .audioInterrupted)
    }

    func test_terminationDuringRecorderStart_isQueuedAndCannotLeaveRecordingStuck() async {
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data(#"{"entry":{"id":"partial3"}}"#.utf8))
        }
        let (sut, store, recorder, _, _) = makeSUT()
        recorder.suspendStart = true

        let startTask = Task { await sut.handle(.startCapture(context: .quick)) }
        while !recorder.isStartSuspended { await Task.yield() }
        await sut.handleRecordingTermination(.audioInterrupted)
        recorder.resumeStart()
        await startTask.value

        let record = store.all().first
        XCTAssertFalse(sut.isRecording)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.stopCallCount, 1)
        XCTAssertEqual(record?.status, .done)
        XCTAssertEqual(record?.audioFileName, "capture-1.m4a")
        XCTAssertEqual(record?.recoveryReason, .audioInterrupted)
    }

    func test_alreadyFinalizedPartial_skipsSecondStopAndUsesRetainedMetadata() async {
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data(#"{"entry":{"id":"partial4"}}"#.utf8))
        }
        let (sut, store, recorder, _, _) = makeSUT()
        let retainedRoute = AudioInputRoute(
            identifier: "airpods-retained",
            name: "AirPods Pro 3",
            portType: "BluetoothHFP"
        )

        await sut.handle(.startCapture(context: .work))
        recorder.isRecording = false // the platform service already finalized it
        let id = store.all().first!.id
        var events: [CaptureCoordinatorEvent] = []
        sut.eventHandler = { events.append($0) }
        await sut.handleFinalizedRecording(
            duration: 4.5,
            recoveryReason: .inputRouteLost,
            inputRoute: retainedRoute
        )

        let record = store.all().first
        XCTAssertFalse(sut.isRecording)
        XCTAssertEqual(recorder.stopCallCount, 0)
        XCTAssertEqual(record?.duration, 4.5)
        XCTAssertEqual(record?.inputRoute, retainedRoute)
        XCTAssertEqual(record?.recoveryReason, .inputRouteLost)
        XCTAssertEqual(record?.status, .done)
        XCTAssertEqual(events, [
            .recordingFinalized(id: id, recoveryReason: .inputRouteLost),
            .completed(id: id),
        ])
    }

    func test_retryAfterTranscriptionFailure_reusesOriginalAudioThenUploads() async {
        let (sut, store, _, transcriber, _) = makeSUT()
        transcriber.result = .failure(.recognizerUnavailable)
        await sut.handle(.startCapture(context: .work))
        await sut.handle(.stopCapture)

        let failed = store.all().first!
        XCTAssertEqual(failed.status, .failed)
        XCTAssertNil(failed.transcript)
        XCTAssertEqual(failed.audioFileName, "capture-1.m4a")

        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data(#"{"entry":{"id":"retried-transcription"}}"#.utf8))
        }
        transcriber.result = .success("recovered transcript")
        var events: [CaptureCoordinatorEvent] = []
        sut.eventHandler = { events.append($0) }
        await sut.retry(id: failed.id)

        let retried = store.record(id: failed.id)
        XCTAssertEqual(transcriber.callCount, 2)
        XCTAssertEqual(retried?.status, .done)
        XCTAssertEqual(retried?.transcript, "recovered transcript")
        XCTAssertEqual(retried?.serverEntryId, "retried-transcription")
        XCTAssertEqual(retried?.audioFileName, "capture-1.m4a")
        XCTAssertEqual(events, [.completed(id: failed.id)])
    }

    func test_retryWithTranscript_skipsTranscriptionAndRetriesUpload() async {
        var uploadCount = 0
        MockURLProtocol.handler = { req in
            uploadCount += 1
            if uploadCount == 1 {
                return (HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
            }
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"entry":{"id":"retried-upload"}}"#.utf8))
        }
        let (sut, store, _, transcriber, _) = makeSUT()
        await sut.handle(.startCapture(context: .ideas))
        await sut.handle(.stopCapture)

        let failed = store.all().first!
        XCTAssertEqual(failed.status, .failed)
        XCTAssertEqual(failed.transcript, "hello")
        XCTAssertEqual(transcriber.callCount, 1)

        var events: [CaptureCoordinatorEvent] = []
        sut.eventHandler = { events.append($0) }
        await sut.retry(id: failed.id)

        let retried = store.record(id: failed.id)
        XCTAssertEqual(transcriber.callCount, 1)
        XCTAssertEqual(retried?.status, .done)
        XCTAssertEqual(retried?.serverEntryId, "retried-upload")
        XCTAssertEqual(retried?.audioFileName, "capture-1.m4a")
        XCTAssertEqual(retried?.retryCount, 1)
        XCTAssertEqual(events, [.completed(id: failed.id)])
    }
}
