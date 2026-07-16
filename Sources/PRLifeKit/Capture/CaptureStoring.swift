import Foundation

@MainActor
public protocol CaptureStoring: AnyObject {
    func insert(_ record: CaptureRecord)
    func update(id: UUID, _ mutate: (inout CaptureRecord) -> Void)
    func remove(id: UUID)
    func all() -> [CaptureRecord]
    func record(id: UUID) -> CaptureRecord?
    /// Confirms that a newly inserted record survived the store's persistence boundary.
    /// In-memory stores are durable for their process lifetime by default; disk-backed
    /// stores should override this after a successful save.
    func isDurablyStored(id: UUID) -> Bool
}

public extension CaptureStoring {
    func isDurablyStored(id: UUID) -> Bool { record(id: id) != nil }
}
