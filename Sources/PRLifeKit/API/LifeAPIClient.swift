import Foundation

public enum LifeAPIError: Error, Equatable, LocalizedError {
    case server(status: Int, body: String)
    case decoding
    case notConfigured
    case invalidBaseURL
    case insecureConnectionRequiresHTTPS

    public var errorDescription: String? {
        switch self {
        case .server(let status, _):
            return "The server request failed with status \(status)."
        case .decoding:
            return "The server response could not be read."
        case .notConfigured:
            return "Set the PR Life base URL and token in Devices before syncing."
        case .invalidBaseURL:
            return "Enter a valid PR Life base URL, such as https://your-pr-life.app or http://localhost:3000."
        case .insecureConnectionRequiresHTTPS:
            return "Remote PR Life servers must use HTTPS. HTTP is only allowed for local development URLs."
        }
    }
}

private struct EntryResponse: Decodable {
    struct Entry: Decodable { let id: String }
    let entry: Entry
}

public final class LifeAPIClient: Sendable {
    private let baseURL: URL
    private let token: String
    private let configurationProvider: (@Sendable () -> (baseURL: URL?, token: String?))?
    private let session: URLSession

    public init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.configurationProvider = nil
        self.session = session
    }

    public init(configurationProvider: @escaping @Sendable () -> (baseURL: URL?, token: String?),
                session: URLSession = .shared) {
        self.baseURL = URL(string: "https://prlife.invalid")!
        self.token = ""
        self.configurationProvider = configurationProvider
        self.session = session
    }

    /// POSTs a voice entry. Returns the server entry id on success.
    @discardableResult
    public func upload(content: String, projectSlug: String?) async throws -> String {
        try await createEntry(content: content, source: "voice", projectSlug: projectSlug)
    }

    /// POSTs a text entry. Returns the server entry id on success.
    @discardableResult
    public func createTextEntry(content: String, projectSlug: String?) async throws -> String {
        try await createEntry(content: content, source: "text", projectSlug: projectSlug)
    }

    @discardableResult
    private func createEntry(content: String, source: String, projectSlug: String?) async throws -> String {
        let (resolvedBaseURL, resolvedToken) = resolvedConfiguration()
        let trimmedToken = resolvedToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let isPlaceholderHost = resolvedBaseURL.host(percentEncoded: false) == "prlife.invalid"
        guard !trimmedToken.isEmpty, !isPlaceholderHost else {
            throw LifeAPIError.notConfigured
        }
        try validateBaseURL(resolvedBaseURL)

        let url = resolvedBaseURL.appendingPathComponent("api/life/entries")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = EntryPayload(content: content, source: source, projectSlug: projectSlug)
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LifeAPIError.decoding }
        guard (200..<300).contains(http.statusCode) else {
            throw LifeAPIError.server(status: http.statusCode,
                                      body: String(data: data, encoding: .utf8) ?? "")
        }
        guard let decoded = try? JSONDecoder().decode(EntryResponse.self, from: data) else {
            throw LifeAPIError.decoding
        }
        return decoded.entry.id
    }

    @discardableResult
    public func createTask(_ payload: TaskPayload) async throws -> LifeTask {
        let (base, token) = try validConfiguration()
        let url = base.appendingPathComponent("api/life/tasks")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        try validate(data, response)
        guard let decoded = try? JSONDecoder().decode(TaskResponse.self, from: data) else {
            throw LifeAPIError.decoding
        }
        return decoded.task
    }

    public func updateTextEntry(id: String, content: String) async throws {
        let (base, token) = try validConfiguration()
        let url = base
            .appendingPathComponent("api")
            .appendingPathComponent("life")
            .appendingPathComponent("entries")
            .appendingPathComponent(id)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(EntryUpdatePayload(content: content))

        let (data, response) = try await session.data(for: request)
        try validate(data, response)
    }

    @discardableResult
    public func updateTask(id: String, title: String) async throws -> LifeTask {
        let (base, token) = try validConfiguration()
        let url = base
            .appendingPathComponent("api")
            .appendingPathComponent("life")
            .appendingPathComponent("tasks")
            .appendingPathComponent(id)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(TaskPayload(title: title))

        let (data, response) = try await session.data(for: request)
        try validate(data, response)
        guard let decoded = try? JSONDecoder().decode(TaskResponse.self, from: data) else {
            throw LifeAPIError.decoding
        }
        return decoded.task
    }

    public func deleteEntry(id: String) async throws {
        let (resolvedBaseURL, resolvedToken) = resolvedConfiguration()
        let trimmedToken = resolvedToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let isPlaceholderHost = resolvedBaseURL.host(percentEncoded: false) == "prlife.invalid"
        guard !trimmedToken.isEmpty, !isPlaceholderHost else {
            throw LifeAPIError.notConfigured
        }
        try validateBaseURL(resolvedBaseURL)

        let url = resolvedBaseURL
            .appendingPathComponent("api")
            .appendingPathComponent("life")
            .appendingPathComponent("entries")
            .appendingPathComponent(id)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LifeAPIError.decoding }
        guard (200..<300).contains(http.statusCode) else {
            throw LifeAPIError.server(status: http.statusCode,
                                      body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    private func resolvedConfiguration() -> (URL, String) {
        guard let configurationProvider else {
            return (baseURL, token)
        }
        let config = configurationProvider()
        return (config.baseURL ?? URL(string: "https://prlife.invalid")!, config.token ?? "")
    }

    // MARK: - Reads (macOS dashboard / widgets)

    private struct TasksResponse: Decodable { let tasks: [LifeTask] }
    private struct TaskResponse: Decodable { let task: LifeTask }
    private struct NotificationsResponse: Decodable { let notifications: [LifeNotification] }
    private struct NotificationResponse: Decodable { let notification: LifeNotification }
    private struct EntryUpdatePayload: Encodable { let content: String }
    private struct NotificationReadPayload: Encodable { let read: Bool }

    /// Resolves config and rejects empty token / placeholder host. Returns trimmed token.
    private func validConfiguration() throws -> (URL, String) {
        let (base, token) = resolvedConfiguration()
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let isPlaceholder = base.host(percentEncoded: false) == "prlife.invalid"
        guard !trimmed.isEmpty, !isPlaceholder else { throw LifeAPIError.notConfigured }
        try validateBaseURL(base)
        return (base, trimmed)
    }

    private func validateBaseURL(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host(percentEncoded: false),
              !host.isEmpty else {
            throw LifeAPIError.invalidBaseURL
        }

        guard LifeAPIBaseURL.allowsInsecureHTTP(url) else {
            throw LifeAPIError.insecureConnectionRequiresHTTPS
        }
    }

    private func authorizedGET(_ url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func validate(_ data: Data, _ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw LifeAPIError.decoding }
        guard (200..<300).contains(http.statusCode) else {
            throw LifeAPIError.server(status: http.statusCode,
                                      body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// Reads `GET /api/life/calendar`. `date` (YYYY-MM-DD) is optional; when nil the
    /// server uses the owner's timezone default.
    public func fetchEvents(date: String?) async throws -> [LifeEvent] {
        try await fetchCalendarDay(date: date).events
    }

    /// Reads a calendar day together with the server's owner-local date and timezone.
    public func fetchCalendarDay(date: String?) async throws -> LifeCalendarDay {
        let (base, token) = try validConfiguration()
        var comps = URLComponents(
            url: base.appendingPathComponent("api/life/calendar"),
            resolvingAgainstBaseURL: false)!
        if let date { comps.queryItems = [URLQueryItem(name: "date", value: date)] }
        let (data, response) = try await session.data(for: authorizedGET(comps.url!, token: token))
        try validate(data, response)
        guard let decoded = try? JSONDecoder().decode(LifeCalendarDay.self, from: data) else {
            throw LifeAPIError.decoding
        }
        return decoded
    }

    /// Reads active tasks from `GET /api/life/tasks?status=active`.
    public func fetchTasks() async throws -> [LifeTask] {
        let (base, token) = try validConfiguration()
        var comps = URLComponents(
            url: base.appendingPathComponent("api/life/tasks"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "status", value: "active")]
        let (data, response) = try await session.data(for: authorizedGET(comps.url!, token: token))
        try validate(data, response)
        guard let decoded = try? JSONDecoder().decode(TasksResponse.self, from: data) else {
            throw LifeAPIError.decoding
        }
        return decoded.tasks
    }

    /// Reads the global notification feed using an installation-local `after` cursor.
    /// Deliberately does not send `unread=true`, because read state is shared by devices.
    public func fetchNotifications(after: Date?, limit: Int = 50) async throws -> [LifeNotification] {
        let (base, token) = try validConfiguration()
        var comps = URLComponents(
            url: base.appendingPathComponent("api/life/notifications"),
            resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = []
        if let after {
            queryItems.append(URLQueryItem(name: "after", value: Self.notificationDateString(after)))
        }
        queryItems.append(URLQueryItem(name: "limit", value: String(min(max(limit, 1), 100))))
        comps.queryItems = queryItems

        let (data, response) = try await session.data(for: authorizedGET(comps.url!, token: token))
        try validate(data, response)
        do {
            return try Self.notificationDecoder().decode(NotificationsResponse.self, from: data).notifications
        } catch {
            throw LifeAPIError.decoding
        }
    }

    @discardableResult
    public func setNotificationRead(id: String, read: Bool) async throws -> LifeNotification {
        let (base, token) = try validConfiguration()
        let url = base
            .appendingPathComponent("api")
            .appendingPathComponent("life")
            .appendingPathComponent("notifications")
            .appendingPathComponent(id)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(NotificationReadPayload(read: read))

        let (data, response) = try await session.data(for: request)
        try validate(data, response)
        do {
            return try Self.notificationDecoder().decode(NotificationResponse.self, from: data).notification
        } catch {
            throw LifeAPIError.decoding
        }
    }

    private static func notificationDateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func notificationDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date: \(value)"
            )
        }
        return decoder
    }
}
