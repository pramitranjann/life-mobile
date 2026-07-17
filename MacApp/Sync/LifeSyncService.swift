import Foundation
import WidgetKit
import PRLifeKit

@MainActor
final class LifeSyncService: ObservableObject {
    enum SyncState: Equatable {
        case idle, syncing, synced(Date), failed(String)
    }

    @Published private(set) var state: SyncState = .idle
    @Published private(set) var snapshot: LifeSnapshot?

    private let api: LifeAPIClient
    private let store: LifeSnapshotStoring
    private let notificationService: LifeNotificationService
    private var timer: Timer?

    init(api: LifeAPIClient,
         notificationService: LifeNotificationService,
         store: LifeSnapshotStoring = CompositeLifeSnapshotStore([
            UserDefaultsLifeSnapshotStore(suiteName: AppGroup.id),
            FileLifeSnapshotStore(directory: AppGroup.containerURL)
         ])) {
        self.api = api
        self.notificationService = notificationService
        self.store = store
        self.snapshot = store.load()
        if let snap = self.snapshot {
            state = .synced(snap.lastSync)
            try? self.store.save(snap)
        }
    }

    func startPeriodicRefresh(interval: TimeInterval = 900) {
        Task { await self.refresh() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        async let notificationRefresh: Void = notificationService.refresh()
        state = .syncing
        do {
            async let events = api.fetchEvents(date: nil)
            async let tasks = api.fetchTasks()
            let snap = LifeSnapshot(
                events: try await events,
                tasks: try await tasks,
                lastSync: Date(),
                localDate: LifeLocalDate.current()
            )
            try store.save(snap)
            snapshot = snap
            state = .synced(snap.lastSync)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            let message = (error as? LifeAPIError)?.errorDescription ?? "\(error)"
            NSLog("[PRLife][sync] refresh failed: %@", "\(error)")
            state = .failed(message)
        }
        await notificationRefresh
    }

    func createQuickNote(_ content: String) async throws {
        try await api.createTextEntry(content: content, projectSlug: nil)
        await refresh()
    }

    func createQuickTask(_ title: String) async throws {
        try await api.createTask(TaskPayload(title: title))
        await refresh()
    }

    /// Completes a task from a row checkbox. On failure the refresh restores
    /// the row, so the checkbox never lies about server state.
    func completeTask(id: String) async {
        do {
            _ = try await api.completeTask(id: id)
        } catch {
            NSLog("[PRLife][sync] complete task failed: %@", "\(error)")
        }
        await refresh()
    }
}
