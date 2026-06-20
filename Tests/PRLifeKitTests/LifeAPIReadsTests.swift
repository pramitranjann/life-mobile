import XCTest
@testable import PRLifeKit

final class LifeAPIReadsTests: XCTestCase {
    private func makeClient() -> LifeAPIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        return LifeAPIClient(baseURL: URL(string: "https://example.com")!,
                             token: "secret-token", session: session)
    }

    func test_fetchEvents_buildsAuthorizedGet_andDecodes() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.httpMethod, "GET")
            XCTAssertEqual(req.url?.absoluteString,
                           "https://example.com/api/life/calendar?date=2026-06-20")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"""
            {"localDate":"2026-06-20","timezone":"Asia/Kuala_Lumpur","events":[
              {"id":"e1","title":"Review","start_time":"2026-06-20T14:00:00+00:00",
               "end_time":null,"all_day":false,"location":null,"local_date":"2026-06-20"}]}
            """#.data(using: .utf8)!
            return (resp, body)
        }
        let events = try await makeClient().fetchEvents(date: "2026-06-20")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.id, "e1")
    }

    func test_fetchTasks_usesActiveStatus_andDecodes() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.httpMethod, "GET")
            XCTAssertEqual(req.url?.absoluteString,
                           "https://example.com/api/life/tasks?status=active")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"""
            {"tasks":[{"id":"t1","title":"Albers","priority":"high",
              "due_local_date":"2026-06-20","project_slug":"albers","status":"open"}]}
            """#.data(using: .utf8)!
            return (resp, body)
        }
        let tasks = try await makeClient().fetchTasks()
        XCTAssertEqual(tasks.first?.priority, .high)
    }

    func test_fetchEvents_throwsNotConfigured_whenPlaceholder() async {
        let client = LifeAPIClient(configurationProvider: { (nil, nil) })
        do { _ = try await client.fetchEvents(date: nil); XCTFail("expected throw") }
        catch { XCTAssertEqual(error as? LifeAPIError, .notConfigured) }
    }
}
