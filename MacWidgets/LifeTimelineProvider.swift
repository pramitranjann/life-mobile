import WidgetKit
import PRLifeKit

struct LifeEntry: TimelineEntry {
    let date: Date
    let snapshot: LifeSnapshot?
}

/// Reads the shared snapshot written by the app. Never hits the network.
struct LifeTimelineProvider: TimelineProvider {
    private let store = FileLifeSnapshotStore(directory: AppGroup.containerURL)

    init() { FontRegistration.registerAll() }

    func placeholder(in context: Context) -> LifeEntry {
        LifeEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (LifeEntry) -> Void) {
        completion(LifeEntry(date: Date(), snapshot: store.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LifeEntry>) -> Void) {
        let entry = LifeEntry(date: Date(), snapshot: store.load())
        let next = Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}
