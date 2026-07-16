import Foundation

@MainActor
public protocol CaptureStoring: AnyObject {
    func insert(_ record: CaptureRecord)
    func update(id: UUID, _ mutate: (inout CaptureRecord) -> Void)
    func remove(id: UUID)
    func all() -> [CaptureRecord]
    func record(id: UUID) -> CaptureRecord?
}
