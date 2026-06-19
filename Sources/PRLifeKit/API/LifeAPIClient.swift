import Foundation

public enum LifeAPIError: Error, Equatable {
    case server(status: Int, body: String)
    case decoding
    case notConfigured
}

private struct EntryResponse: Decodable {
    struct Entry: Decodable { let id: String }
    let entry: Entry
}

public final class LifeAPIClient: @unchecked Sendable {
    private let baseURL: URL
    private let token: String
    private let session: URLSession

    public init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    /// POSTs a voice entry. Returns the server entry id on success.
    @discardableResult
    @available(macOS 12, *)
    public func upload(content: String, projectSlug: String?) async throws -> String? {
        let url = baseURL.appendingPathComponent("api/life/entries")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = EntryPayload(content: content, projectSlug: projectSlug)
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LifeAPIError.decoding }
        guard (200..<300).contains(http.statusCode) else {
            throw LifeAPIError.server(status: http.statusCode,
                                      body: String(data: data, encoding: .utf8) ?? "")
        }
        return (try? JSONDecoder().decode(EntryResponse.self, from: data))?.entry.id
    }
}
