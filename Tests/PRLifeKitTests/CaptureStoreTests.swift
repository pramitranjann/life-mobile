import XCTest
@testable import PRLifeKit

final class CaptureStoreTests: XCTestCase {
    func test_insert_thenUpdateStatus() {
        let store = InMemoryCaptureStore()
        let rec = CaptureRecord(context: .quick)
        store.insert(rec)
        store.update(id: rec.id) { $0.status = .processing }
        XCTAssertEqual(store.record(id: rec.id)?.status, .processing)
    }

    func test_all_returnsNewestFirst() {
        let store = InMemoryCaptureStore()
        let a = CaptureRecord(createdAt: Date(timeIntervalSince1970: 1), context: .work)
        let b = CaptureRecord(createdAt: Date(timeIntervalSince1970: 2), context: .ideas)
        store.insert(a); store.insert(b)
        XCTAssertEqual(store.all().first?.id, b.id)
    }
}
