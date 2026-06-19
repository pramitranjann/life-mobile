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
}
