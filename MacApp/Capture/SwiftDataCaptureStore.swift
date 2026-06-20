import Foundation
import SwiftData
import PRLifeKit

@Model
final class CaptureEntity {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var duration: TimeInterval
    var contextRaw: String
    var audioFileName: String?
    var transcript: String?
    var statusRaw: String
    var serverEntryId: String?
    var lastError: String?
    var retryCount: Int

    init(_ r: CaptureRecord) {
        id = r.id; createdAt = r.createdAt; duration = r.duration
        contextRaw = r.context.rawValue; audioFileName = r.audioFileName
        transcript = r.transcript; statusRaw = r.status.rawValue
        serverEntryId = r.serverEntryId; lastError = r.lastError; retryCount = r.retryCount
    }
    var record: CaptureRecord {
        CaptureRecord(id: id, createdAt: createdAt, duration: duration,
                      context: CaptureContext(rawValue: contextRaw) ?? .quick,
                      audioFileName: audioFileName, transcript: transcript,
                      status: CaptureStatus(rawValue: statusRaw) ?? .failed,
                      serverEntryId: serverEntryId, lastError: lastError, retryCount: retryCount)
    }
    func apply(_ r: CaptureRecord) {
        // id/createdAt/context are immutable post-insert; intentionally not applied.
        duration = r.duration; audioFileName = r.audioFileName; transcript = r.transcript
        statusRaw = r.status.rawValue; serverEntryId = r.serverEntryId
        lastError = r.lastError; retryCount = r.retryCount
    }
}

@MainActor
final class SwiftDataCaptureStore: CaptureStoring {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func insert(_ record: CaptureRecord) {
        context.insert(CaptureEntity(record)); try? context.save()
    }
    func update(id: UUID, _ mutate: (inout CaptureRecord) -> Void) {
        guard let e = fetch(id) else { return }
        var r = e.record; mutate(&r); e.apply(r); try? context.save()
    }
    func remove(id: UUID) {
        guard let e = fetch(id) else { return }
        context.delete(e)
        try? context.save()
    }
    func all() -> [CaptureRecord] {
        let d = FetchDescriptor<CaptureEntity>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return ((try? context.fetch(d)) ?? []).map(\.record)
    }
    func record(id: UUID) -> CaptureRecord? { fetch(id)?.record }
    private func fetch(_ id: UUID) -> CaptureEntity? {
        let d = FetchDescriptor<CaptureEntity>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(d).first
    }
}
