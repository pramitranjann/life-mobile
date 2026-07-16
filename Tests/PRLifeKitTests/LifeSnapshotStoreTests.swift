import XCTest
@testable import PRLifeKit

final class LifeSnapshotStoreTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snap-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeSnapshot() -> LifeSnapshot {
        let event = LifeEvent(id: "e1", title: "Review", startTime: "2026-06-20T14:00:00+00:00",
                              endTime: nil, allDay: false, location: nil, localDate: "2026-06-20")
        let task = LifeTask(id: "t1", title: "Albers", priority: .high,
                            dueLocalDate: "2026-06-20", projectSlug: "albers", status: "open")
        return LifeSnapshot(events: [event], tasks: [task],
                            lastSync: Date(timeIntervalSince1970: 1_750_000_000),
                            localDate: "2025-06-15")
    }

    func test_load_returnsNil_whenNoFile() {
        let store = FileLifeSnapshotStore(directory: tempDir())
        XCTAssertNil(store.load())
    }

    func test_saveThenLoad_roundTrips() throws {
        let dir = tempDir()
        let store = FileLifeSnapshotStore(directory: dir)
        let snapshot = makeSnapshot()

        try store.save(snapshot)
        let loaded = store.load()

        XCTAssertEqual(loaded, snapshot)
        XCTAssertEqual(loaded?.events.first?.id, "e1")
        XCTAssertEqual(loaded?.tasks.first?.priority, .high)
        XCTAssertEqual(loaded?.localDate, "2025-06-15")
        XCTAssertEqual(loaded?.generatedAt, snapshot.generatedAt)
    }

    func test_load_decodesLegacyLastSyncSnapshot() throws {
        let legacy = #"{"events":[],"tasks":[],"lastSync":750000000,"localDate":"2026-07-16"}"#
        let snapshot = try JSONDecoder().decode(LifeSnapshot.self, from: Data(legacy.utf8))

        XCTAssertEqual(snapshot.generatedAt, Date(timeIntervalSinceReferenceDate: 750_000_000))
        XCTAssertEqual(snapshot.lastSync, snapshot.generatedAt)
    }

    func test_encode_includesGeneratedAtAndLegacyLastSync() throws {
        let data = try JSONEncoder().encode(makeSnapshot())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNotNil(object["generatedAt"])
        XCTAssertEqual(object["generatedAt"] as? Double, object["lastSync"] as? Double)
    }

    func test_snapshotAge_labelsRecentAndStaleData() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        XCTAssertEqual(
            LifeSnapshotAge(generatedAt: now.addingTimeInterval(-18 * 60), now: now).label,
            "UPDATED 18M AGO"
        )
        XCTAssertEqual(
            LifeSnapshotAge(generatedAt: now.addingTimeInterval(-3 * 60 * 60), now: now).label,
            "STALE · UPDATED 3H AGO"
        )
    }

    func test_userDefaultsStore_roundTrips() throws {
        let suiteName = "prlife.tests.\(UUID().uuidString)"
        let store = UserDefaultsLifeSnapshotStore(suiteName: suiteName)
        let snapshot = makeSnapshot()

        try store.save(snapshot)
        XCTAssertEqual(store.load(), snapshot)

        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    func test_compositeStore_readsFromFirstStoreWithSnapshot() throws {
        let suiteName = "prlife.tests.\(UUID().uuidString)"
        let defaultsStore = UserDefaultsLifeSnapshotStore(suiteName: suiteName)
        let fileStore = FileLifeSnapshotStore(directory: tempDir())
        let snapshot = makeSnapshot()

        try defaultsStore.save(snapshot)
        let composite = CompositeLifeSnapshotStore([defaultsStore, fileStore])

        XCTAssertEqual(composite.load(), snapshot)
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    func test_compositeStore_prefersNewestSnapshot() throws {
        let suiteName = "prlife.tests.\(UUID().uuidString)"
        let defaultsStore = UserDefaultsLifeSnapshotStore(suiteName: suiteName)
        let fileStore = FileLifeSnapshotStore(directory: tempDir())

        let stale = LifeSnapshot(
            events: [],
            tasks: [],
            lastSync: Date(timeIntervalSince1970: 1_750_000_000),
            localDate: "2026-06-25"
        )
        let fresh = LifeSnapshot(
            events: [],
            tasks: [
                LifeTask(
                    id: "t2",
                    title: "AI Plan Decision",
                    priority: .medium,
                    dueLocalDate: "2026-06-25",
                    projectSlug: "ops",
                    status: "open"
                )
            ],
            lastSync: Date(timeIntervalSince1970: 1_750_000_100),
            localDate: "2026-06-25"
        )

        try defaultsStore.save(stale)
        try fileStore.save(fresh)

        let composite = CompositeLifeSnapshotStore([defaultsStore, fileStore])
        XCTAssertEqual(composite.load(), fresh)

        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    func test_compositeStore_prefersRicherSnapshot_whenSyncTimesMatch() throws {
        let suiteName = "prlife.tests.\(UUID().uuidString)"
        let defaultsStore = UserDefaultsLifeSnapshotStore(suiteName: suiteName)
        let fileStore = FileLifeSnapshotStore(directory: tempDir())
        let syncTime = Date(timeIntervalSince1970: 1_750_000_000)

        let sparse = LifeSnapshot(events: [], tasks: [], lastSync: syncTime, localDate: "2026-06-25")
        let rich = makeSnapshot()

        try defaultsStore.save(sparse)
        try fileStore.save(LifeSnapshot(
            events: rich.events,
            tasks: rich.tasks,
            lastSync: syncTime,
            localDate: rich.localDate
        ))

        let composite = CompositeLifeSnapshotStore([defaultsStore, fileStore])
        XCTAssertEqual(composite.load()?.tasks.count, 1)
        XCTAssertEqual(composite.load()?.events.count, 1)

        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }
}
