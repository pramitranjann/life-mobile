import XCTest
@testable import PRLifeKit

final class LifeAPIClientTests: XCTestCase {
    private func makeClient() -> LifeAPIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        return LifeAPIClient(
            baseURL: URL(string: "https://example.com")!,
            token: "secret-token",
            session: session
        )
    }

    func test_upload_buildsAuthorizedJSONPost() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(req.url?.absoluteString, "https://example.com/api/life/entries")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"entry":{"id":"abc123"}}"#.data(using: .utf8)!
            return (resp, body)
        }
        let client = makeClient()
        let entryId = try await client.upload(content: "hello world", projectSlug: "work")

        let sent = try XCTUnwrap(MockURLProtocol.lastRequestBody)
        let payload = try JSONDecoder().decode(EntryPayload.self, from: sent)
        XCTAssertEqual(payload.content, "hello world")
        XCTAssertEqual(payload.source, "voice")
        XCTAssertEqual(payload.projectSlug, "work")
        XCTAssertEqual(entryId, "abc123")
    }

    func test_upload_throwsOnServerError() async {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (resp, Data("{\"error\":\"boom\"}".utf8))
        }
        let client = makeClient()
        do {
            _ = try await client.upload(content: "x", projectSlug: nil)
            XCTFail("expected throw")
        } catch let LifeAPIError.server(status, _) {
            XCTAssertEqual(status, 500)
        } catch { XCTFail("wrong error: \(error)") }
    }

    func test_upload_throwsDecodingOn2xxWithBadBody() async {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data("not json".utf8))
        }
        let client = makeClient()
        do {
            _ = try await client.upload(content: "x", projectSlug: nil)
            XCTFail("expected throw")
        } catch LifeAPIError.decoding {
            // expected
        } catch { XCTFail("wrong error: \(error)") }
    }
}
