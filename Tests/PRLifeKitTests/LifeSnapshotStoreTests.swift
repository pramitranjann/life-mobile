import XCTest
@testable import PRLifeKit

final class LifeSnapshotStoreTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snap-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func test_load_returnsNil_whenNoFile() {
        let store = FileLifeSnapshotStore(directory: tempDir())
        XCTAssertNil(store.load())
    }

    func test_saveThenLoad_roundTrips() throws {
        let dir = tempDir()
        let store = FileLifeSnapshotStore(directory: dir)
        let event = LifeEvent(id: "e1", title: "Review", startTime: "2026-06-20T14:00:00+00:00",
                              endTime: nil, allDay: false, location: nil, localDate: "2026-06-20")
        let task = LifeTask(id: "t1", title: "Albers", priority: .high,
                            dueLocalDate: "2026-06-20", projectSlug: "albers", status: "open")
        let snapshot = LifeSnapshot(events: [event], tasks: [task],
                                    lastSync: Date(timeIntervalSince1970: 1_750_000_000))

        try store.save(snapshot)
        let loaded = store.load()

        XCTAssertEqual(loaded, snapshot)
        XCTAssertEqual(loaded?.events.first?.id, "e1")
        XCTAssertEqual(loaded?.tasks.first?.priority, .high)
    }
}
