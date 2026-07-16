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

    func test_fetchNotifications_buildsAuthorizedCursorGet_andDecodesDatesAndMetadata() async throws {
        let after = try XCTUnwrap(LifeEvent.parseISO("2026-07-16T00:00:00.000Z"))
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.httpMethod, "GET")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
            let components = try XCTUnwrap(URLComponents(url: req.url!, resolvingAgainstBaseURL: false))
            XCTAssertEqual(components.path, "/api/life/notifications")
            XCTAssertEqual(components.queryItems?.first(where: { $0.name == "after" })?.value,
                           "2026-07-16T00:00:00.000Z")
            XCTAssertEqual(components.queryItems?.first(where: { $0.name == "limit" })?.value, "50")
            XCTAssertNil(components.queryItems?.first(where: { $0.name == "unread" }))

            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"""
            {"notifications":[
              {"id":"n1","user_id":"owner","kind":"program_application",
               "title":"Applications open","body":"Apply now","url":"https://example.com/apply",
               "metadata":{"programKey":"codex-ambassadors","status":"open"},
               "dedupe_key":"program-application:codex-ambassadors:hash",
               "created_at":"2026-07-16T14:30:00.123Z","read_at":null},
              {"id":"n2","user_id":"owner","kind":"program_application",
               "title":"Date announced","body":"Applications open soon","url":null,
               "metadata":{"programKey":"claude-campus-ambassador","status":"date_announced"},
               "dedupe_key":"program-application:claude-campus-ambassador:hash",
               "created_at":"2026-07-16T15:30:00Z","read_at":"2026-07-16T16:00:00Z"}
            ]}
            """#.data(using: .utf8)!
            return (resp, body)
        }

        let notifications = try await makeClient().fetchNotifications(after: after)
        XCTAssertEqual(notifications.map(\.id), ["n1", "n2"])
        XCTAssertEqual(notifications[0].metadata["programKey"], "codex-ambassadors")
        XCTAssertEqual(notifications[0].url?.absoluteString, "https://example.com/apply")
        XCTAssertNotNil(notifications[0].createdAt)
        XCTAssertNotNil(notifications[1].readAt)
    }

    func test_setNotificationRead_buildsAuthorizedPatch_andDecodesResponse() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.httpMethod, "PATCH")
            XCTAssertEqual(req.url?.absoluteString, "https://example.com/api/life/notifications/n1")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"""
            {"notification":{"id":"n1","kind":"program_application","title":"Open","body":"Apply",
              "url":null,"metadata":{"status":"open"},"created_at":"2026-07-16T14:30:00.000Z",
              "read_at":"2026-07-16T14:31:00.000Z"}}
            """#.data(using: .utf8)!
            return (resp, body)
        }

        let notification = try await makeClient().setNotificationRead(id: "n1", read: true)
        let body = try XCTUnwrap(MockURLProtocol.lastRequestBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Bool])
        XCTAssertEqual(json["read"], true)
        XCTAssertEqual(notification.id, "n1")
        XCTAssertNotNil(notification.readAt)
    }

    func test_fetchNotifications_mapsUnauthorizedAndMalformedResponses() async {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, Data(#"{"error":"unauthorized"}"#.utf8))
        }

        do {
            _ = try await makeClient().fetchNotifications(after: nil)
            XCTFail("expected server error")
        } catch let LifeAPIError.server(status, _) {
            XCTAssertEqual(status, 401)
        } catch {
            XCTFail("wrong error: \(error)")
        }

        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(#"{"notifications":"bad"}"#.utf8))
        }
        do {
            _ = try await makeClient().fetchNotifications(after: nil)
            XCTFail("expected decoding error")
        } catch {
            XCTAssertEqual(error as? LifeAPIError, .decoding)
        }
    }
}
