import Foundation

public struct LifeAPIConfiguration: Codable, Equatable, Sendable {
    public let baseURL: String
    public let token: String

    public init(baseURL: String, token: String) {
        self.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public protocol LifeAPIConfigurationStoring: Sendable {
    func load() -> LifeAPIConfiguration?
    func save(_ configuration: LifeAPIConfiguration) throws
}

/// Persists API configuration as JSON so the app and widget can read the exact same file
/// from the App Group container.
public final class FileLifeAPIConfigurationStore: LifeAPIConfigurationStoring {
    private let url: URL

    public init(directory: URL, fileName: String = "life-api-config.json") {
        self.url = directory.appendingPathComponent(fileName)
    }

    public func load() -> LifeAPIConfiguration? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LifeAPIConfiguration.self, from: data)
    }

    public func save(_ configuration: LifeAPIConfiguration) throws {
        let data = try JSONEncoder().encode(configuration)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
