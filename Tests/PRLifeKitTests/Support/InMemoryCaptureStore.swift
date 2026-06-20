import Foundation
@testable import PRLifeKit

final class InMemoryCaptureStore: CaptureStoring, @unchecked Sendable {
    private(set) var records: [CaptureRecord] = []

    func insert(_ record: CaptureRecord) { records.insert(record, at: 0) }

    func update(id: UUID, _ mutate: (inout CaptureRecord) -> Void) {
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        mutate(&records[i])
    }

    func remove(id: UUID) {
        records.removeAll { $0.id == id }
    }

    func all() -> [CaptureRecord] { records }

    func record(id: UUID) -> CaptureRecord? { records.first { $0.id == id } }
}
