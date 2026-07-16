import Foundation
import SwiftData
import PRLifeKit

@Model
final class CaptureEntity {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var duration: TimeInterval
    var contextRaw: String
    var modeRaw: String = CaptureMode.voice.rawValue
    var projectSlug: String?
    var taskDueLocalDate: String?
    var audioFileName: String?
    var transcript: String?
    var statusRaw: String
    var serverEntryId: String?
    var lastError: String?
    var retryCount: Int
    var inputRouteIdentifier: String?
    var inputRouteName: String?
    var inputRoutePortType: String?
    var recoveryReasonRaw: String?

    init(_ r: CaptureRecord) {
        id = r.id; createdAt = r.createdAt; duration = r.duration
        contextRaw = r.context.rawValue; modeRaw = r.mode.rawValue
        projectSlug = r.projectSlug; taskDueLocalDate = r.taskDueLocalDate
        audioFileName = r.audioFileName
        transcript = r.transcript; statusRaw = r.status.rawValue
        serverEntryId = r.serverEntryId; lastError = r.lastError; retryCount = r.retryCount
        inputRouteIdentifier = r.inputRoute?.identifier
        inputRouteName = r.inputRoute?.name
        inputRoutePortType = r.inputRoute?.portType
        recoveryReasonRaw = r.recoveryReason?.rawValue
    }
    var record: CaptureRecord {
        let route: AudioInputRoute?
        if let inputRouteIdentifier, let inputRouteName, let inputRoutePortType {
            route = AudioInputRoute(
                identifier: inputRouteIdentifier,
                name: inputRouteName,
                portType: inputRoutePortType
            )
        } else {
            route = nil
        }
        return CaptureRecord(id: id, createdAt: createdAt, duration: duration,
                             context: CaptureContext(rawValue: contextRaw) ?? .quick,
                             mode: CaptureMode(rawValue: modeRaw) ?? .voice,
                             projectSlug: projectSlug,
                             taskDueLocalDate: taskDueLocalDate,
                             audioFileName: audioFileName, transcript: transcript,
                             status: CaptureStatus(rawValue: statusRaw) ?? .failed,
                             serverEntryId: serverEntryId, lastError: lastError, retryCount: retryCount,
                             inputRoute: route,
                             recoveryReason: recoveryReasonRaw.flatMap(CaptureRecoveryReason.init(rawValue:)))
    }
    func apply(_ r: CaptureRecord) {
        // id/createdAt are immutable post-insert; intentionally not applied.
        duration = r.duration; audioFileName = r.audioFileName; transcript = r.transcript
        contextRaw = r.context.rawValue; modeRaw = r.mode.rawValue
        projectSlug = r.projectSlug; taskDueLocalDate = r.taskDueLocalDate
        statusRaw = r.status.rawValue; serverEntryId = r.serverEntryId
        lastError = r.lastError; retryCount = r.retryCount
        inputRouteIdentifier = r.inputRoute?.identifier
        inputRouteName = r.inputRoute?.name
        inputRoutePortType = r.inputRoute?.portType
        recoveryReasonRaw = r.recoveryReason?.rawValue
    }
}

@MainActor
final class SwiftDataCaptureStore: CaptureStoring {
    private let context: ModelContext
    private var persistedIDs: Set<UUID>

    init(context: ModelContext) {
        self.context = context
        let descriptor = FetchDescriptor<CaptureEntity>()
        persistedIDs = Set(((try? context.fetch(descriptor)) ?? []).map(\.id))
    }

    func insert(_ record: CaptureRecord) {
        context.insert(CaptureEntity(record))
        do {
            try context.save()
            persistedIDs.insert(record.id)
        } catch {
            NSLog("[PRLife][capture-store] insert failed: %@", error.localizedDescription)
        }
    }
    func update(id: UUID, _ mutate: (inout CaptureRecord) -> Void) {
        guard let e = fetch(id) else { return }
        var r = e.record; mutate(&r); e.apply(r)
        do {
            try context.save()
            persistedIDs.insert(id)
        } catch {
            NSLog("[PRLife][capture-store] update failed: %@", error.localizedDescription)
        }
    }
    func remove(id: UUID) {
        guard let e = fetch(id) else { return }
        context.delete(e)
        do {
            try context.save()
            persistedIDs.remove(id)
        } catch {
            NSLog("[PRLife][capture-store] delete failed: %@", error.localizedDescription)
        }
    }
    func all() -> [CaptureRecord] {
        let d = FetchDescriptor<CaptureEntity>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return ((try? context.fetch(d)) ?? []).map(\.record)
    }
    func record(id: UUID) -> CaptureRecord? { fetch(id)?.record }
    func isDurablyStored(id: UUID) -> Bool { persistedIDs.contains(id) }
    private func fetch(_ id: UUID) -> CaptureEntity? {
        let d = FetchDescriptor<CaptureEntity>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(d).first
    }
}
