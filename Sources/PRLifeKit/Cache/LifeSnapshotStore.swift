import Foundation
#if canImport(Darwin)
import Darwin
#endif

public protocol LifeSnapshotStoring {
    func load() -> LifeSnapshot?
    func save(_ snapshot: LifeSnapshot) throws
}

public enum LifeSnapshotLocation {
    public static func fileURL(in containerDirectory: URL) -> URL {
        containerDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("PRLife", isDirectory: true)
            .appendingPathComponent("life-snapshot.json")
    }
}

/// Persists the snapshot as JSON. In the app it is constructed with the App Group
/// container directory so the widget extension reads the same file.
public final class FileLifeSnapshotStore: LifeSnapshotStoring {
    private let url: URL

    public init(directory: URL, fileName: String = "life-snapshot.json") {
        if fileName == "life-snapshot.json" {
            self.url = LifeSnapshotLocation.fileURL(in: directory)
        } else {
            self.url = directory.appendingPathComponent(fileName)
        }
    }

    public func load() -> LifeSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LifeSnapshot.self, from: data)
    }

    public func save(_ snapshot: LifeSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
        clearExtendedAttributes(at: url.deletingLastPathComponent())
        clearExtendedAttributes(at: url)
    }

    private func clearExtendedAttributes(at url: URL) {
        #if canImport(Darwin)
        url.path.withCString { path in
            _ = removexattr(path, "com.apple.quarantine", 0)
            _ = removexattr(path, "com.apple.provenance", 0)
        }
        #endif
    }
}

/// Persists the snapshot as JSON-encoded Data inside a shared UserDefaults suite.
public final class UserDefaultsLifeSnapshotStore: LifeSnapshotStoring {
    private let defaults: UserDefaults?
    private let key: String

    public init(suiteName: String, key: String = "lifeSnapshot") {
        self.defaults = UserDefaults(suiteName: suiteName)
        self.key = key
    }

    public func load() -> LifeSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LifeSnapshot.self, from: data)
    }

    public func save(_ snapshot: LifeSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        defaults?.set(data, forKey: key)
        defaults?.synchronize()
    }
}

/// Writes to every store and reads from the first store that has a snapshot.
public final class CompositeLifeSnapshotStore: LifeSnapshotStoring {
    private let stores: [LifeSnapshotStoring]

    public init(_ stores: [LifeSnapshotStoring]) {
        self.stores = stores
    }

    public func load() -> LifeSnapshot? {
        stores
            .compactMap { $0.load() }
            .max(by: isLowerPriority(_:than:))
    }

    public func save(_ snapshot: LifeSnapshot) throws {
        for store in stores {
            try store.save(snapshot)
        }
    }

    private func isLowerPriority(_ lhs: LifeSnapshot, than rhs: LifeSnapshot) -> Bool {
        if lhs.lastSync != rhs.lastSync {
            return lhs.lastSync < rhs.lastSync
        }

        let lhsContent = lhs.events.count + lhs.tasks.count
        let rhsContent = rhs.events.count + rhs.tasks.count
        if lhsContent != rhsContent {
            return lhsContent < rhsContent
        }

        return false
    }
}
