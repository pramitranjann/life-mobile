import Foundation

public protocol CaptureStoring: AnyObject, Sendable {
    func insert(_ record: CaptureRecord)
    func update(id: UUID, _ mutate: (inout CaptureRecord) -> Void)
    func all() -> [CaptureRecord]
    func record(id: UUID) -> CaptureRecord?
}
