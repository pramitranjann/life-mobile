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

    func test_upload_throwsNotConfiguredWhenTokenMissing() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = LifeAPIClient(
            baseURL: URL(string: "https://prlife.invalid")!,
            token: "   ",
            session: URLSession(configuration: config)
        )

        do {
            _ = try await client.upload(content: "x", projectSlug: nil)
            XCTFail("expected throw")
        } catch LifeAPIError.notConfigured {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_upload_usesDynamicConfigurationProvider() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.absoluteString, "https://dynamic.example/api/life/entries")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer dynamic-token")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"entry":{"id":"dyn123"}}"#.data(using: .utf8)!
            return (resp, body)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let client = LifeAPIClient(configurationProvider: {
            (URL(string: "https://dynamic.example"), "dynamic-token")
        }, session: session)

        let entryId = try await client.upload(content: "dynamic", projectSlug: nil)
        XCTAssertEqual(entryId, "dyn123")
    }

    func test_deleteEntry_buildsAuthorizedDelete() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.httpMethod, "DELETE")
            XCTAssertEqual(req.url?.absoluteString, "https://example.com/api/life/entries/abc123")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }

        let client = makeClient()
        try await client.deleteEntry(id: "abc123")
    }

    func test_deleteEntry_throwsOnServerError() async {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (resp, Data("{\"error\":\"missing\"}".utf8))
        }

        let client = makeClient()
        do {
            try await client.deleteEntry(id: "missing")
            XCTFail("expected throw")
        } catch let LifeAPIError.server(status, _) {
            XCTAssertEqual(status, 404)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
