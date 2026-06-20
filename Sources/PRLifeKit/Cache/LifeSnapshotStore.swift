import Foundation

public protocol LifeSnapshotStoring: Sendable {
    func load() -> LifeSnapshot?
    func save(_ snapshot: LifeSnapshot) throws
}

/// Persists the snapshot as JSON. In the app it is constructed with the App Group
/// container directory so the widget extension reads the same file.
public final class FileLifeSnapshotStore: LifeSnapshotStoring {
    private let url: URL

    public init(directory: URL, fileName: String = "life-snapshot.json") {
        self.url = directory.appendingPathComponent(fileName)
    }

    public func load() -> LifeSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LifeSnapshot.self, from: data)
    }

    public func save(_ snapshot: LifeSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
    }
}
