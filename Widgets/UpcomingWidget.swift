import WidgetKit
import SwiftUI
import PRLifeKit

enum UpcomingState: Equatable {
    case current
    case cachedAfterTemporaryFailure
    case configurationRequired
    case authenticationRequired
    case temporaryFailure

    var showsCachedContent: Bool { self == .cachedAfterTemporaryFailure }
}

struct UpcomingEntry: TimelineEntry {
    let date: Date
    let events: [LifeEvent]
    let tasks: [LifeTask]
    let generatedAt: Date?
    let state: UpcomingState
}

struct UpcomingProvider: TimelineProvider {
    private let snapshotStore: LifeSnapshotStoring

    init(snapshotStore: LifeSnapshotStoring = UpcomingProvider.makeSnapshotStore()) {
        self.snapshotStore = snapshotStore
    }

    private static func makeSnapshotStore() -> LifeSnapshotStoring {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return FileLifeSnapshotStore(directory: directory, fileName: "widget-upcoming-snapshot.json")
    }

    private func makeClient() -> LifeAPIClient {
        LifeAPIClient(configurationProvider: {
            (LifeAPIBaseURL.normalizedURL(from: KeychainConfig.baseURL), KeychainConfig.token)
        })
    }

    func placeholder(in context: Context) -> UpcomingEntry {
        UpcomingEntry(
            date: .now,
            events: UpcomingSample.events,
            tasks: UpcomingSample.tasks,
            generatedAt: .now,
            state: .current
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (UpcomingEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        if let cached = snapshotStore.load() {
            completion(entry(from: cached, state: .cachedAfterTemporaryFailure))
        } else {
            completion(UpcomingEntry(
                date: .now,
                events: [],
                tasks: [],
                generatedAt: nil,
                state: .temporaryFailure
            ))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UpcomingEntry>) -> Void) {
        let client = makeClient()
        Task {
            let next = Date().addingTimeInterval(30 * 60)
            do {
                async let day = client.fetchCalendarDay(date: nil)
                async let tasks = client.fetchTasks()
                let (resolvedDay, resolvedTasks) = try await (day, tasks)
                let snapshot = LifeSnapshot(
                    events: resolvedDay.events,
                    tasks: resolvedTasks,
                    generatedAt: .now,
                    localDate: resolvedDay.localDate
                )
                do {
                    try snapshotStore.save(snapshot)
                } catch {
                    NSLog("[PRLife][widget] could not persist last-success snapshot: %@", error.localizedDescription)
                }
                let entry = entry(from: snapshot, state: .current)
                completion(Timeline(entries: [entry], policy: .after(next)))
            } catch {
                let failure = LifeWidgetSnapshotPolicy.classify(error)
                let state = failureState(for: failure)
                let entry: UpcomingEntry
                if let cached = LifeWidgetSnapshotPolicy.cachedSnapshot(
                    after: failure,
                    from: snapshotStore
                ) {
                    entry = self.entry(from: cached, state: .cachedAfterTemporaryFailure)
                } else {
                    entry = UpcomingEntry(
                        date: .now,
                        events: [],
                        tasks: [],
                        generatedAt: nil,
                        state: state
                    )
                }
                completion(Timeline(entries: [entry], policy: .after(next)))
            }
        }
    }

    private func entry(from snapshot: LifeSnapshot, state: UpcomingState) -> UpcomingEntry {
        UpcomingEntry(
            date: .now,
            events: snapshot.events,
            tasks: snapshot.tasks,
            generatedAt: snapshot.generatedAt,
            state: state
        )
    }

    private func failureState(for failure: LifeWidgetLoadFailure) -> UpcomingState {
        switch failure {
        case .configurationRequired:
            return .configurationRequired
        case .authenticationRequired:
            return .authenticationRequired
        case .temporary:
            return .temporaryFailure
        }
    }
}

enum UpcomingSample {
    private static func iso(_ secs: TimeInterval) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(secs))
    }
    static let events = [
        LifeEvent(id: "1", title: "Review Session", startTime: iso(1320), endTime: nil, allDay: false, location: nil, localDate: ""),
        LifeEvent(id: "2", title: "Studio Time", startTime: iso(7200), endTime: nil, allDay: false, location: nil, localDate: ""),
    ]
    static let tasks = [
        LifeTask(id: "1", title: "Finish Albers brief", priority: .high, dueLocalDate: nil, projectSlug: "albers", status: "open"),
        LifeTask(id: "2", title: "Review gym log", priority: .medium, dueLocalDate: nil, projectSlug: "body", status: "open"),
    ]
}

struct UpcomingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LifeWidgetKind.upcoming, provider: UpcomingProvider()) { entry in
            UpcomingWidgetView(entry: entry)
        }
        .configurationDisplayName("Upcoming")
        .description("Your next events and due tasks.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}
