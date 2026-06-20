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
    private var timer: Timer?

    init(api: LifeAPIClient,
         store: LifeSnapshotStoring = FileLifeSnapshotStore(directory: AppGroup.containerURL)) {
        self.api = api
        self.store = store
        self.snapshot = store.load()
        if let snap = self.snapshot { state = .synced(snap.lastSync) }
    }

    func startPeriodicRefresh(interval: TimeInterval = 900) {
        Task { await self.refresh() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        state = .syncing
        do {
            async let events = api.fetchEvents(date: nil)
            async let tasks = api.fetchTasks()
            let snap = LifeSnapshot(events: try await events, tasks: try await tasks, lastSync: Date())
            try store.save(snap)
            snapshot = snap
            state = .synced(snap.lastSync)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            let message = (error as? LifeAPIError)?.errorDescription ?? "\(error)"
            state = .failed(message)
        }
    }
}
