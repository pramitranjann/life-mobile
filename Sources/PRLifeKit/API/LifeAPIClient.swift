import Foundation

public enum LifeAPIError: Error, Equatable, LocalizedError {
    case server(status: Int, body: String)
    case decoding
    case notConfigured

    public var errorDescription: String? {
        switch self {
        case .server(let status, _):
            return "The server request failed with status \(status)."
        case .decoding:
            return "The server response could not be read."
        case .notConfigured:
            return "Set the PR Life base URL and token in Devices before syncing."
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
        let (resolvedBaseURL, resolvedToken) = resolvedConfiguration()
        let trimmedToken = resolvedToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let isPlaceholderHost = resolvedBaseURL.host(percentEncoded: false) == "prlife.invalid"
        guard !trimmedToken.isEmpty, !isPlaceholderHost else {
            throw LifeAPIError.notConfigured
        }

        let url = resolvedBaseURL.appendingPathComponent("api/life/entries")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = EntryPayload(content: content, projectSlug: projectSlug)
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

    public func deleteEntry(id: String) async throws {
        let (resolvedBaseURL, resolvedToken) = resolvedConfiguration()
        let trimmedToken = resolvedToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let isPlaceholderHost = resolvedBaseURL.host(percentEncoded: false) == "prlife.invalid"
        guard !trimmedToken.isEmpty, !isPlaceholderHost else {
            throw LifeAPIError.notConfigured
        }

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
}
