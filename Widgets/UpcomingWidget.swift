import WidgetKit
import SwiftUI
import PRLifeKit

enum UpcomingState { case ok, notConfigured, failed }

struct UpcomingEntry: TimelineEntry {
    let date: Date
    let events: [LifeEvent]
    let tasks: [LifeTask]
    let state: UpcomingState
}

struct UpcomingProvider: TimelineProvider {
    private func makeClient() -> LifeAPIClient {
        LifeAPIClient(configurationProvider: {
            let trimmed = KeychainConfig.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (URL(string: trimmed), KeychainConfig.token)
        })
    }

    func placeholder(in context: Context) -> UpcomingEntry {
        UpcomingEntry(date: .now, events: UpcomingSample.events, tasks: UpcomingSample.tasks, state: .ok)
    }

    func getSnapshot(in context: Context, completion: @escaping (UpcomingEntry) -> Void) {
        completion(UpcomingEntry(date: .now, events: UpcomingSample.events, tasks: UpcomingSample.tasks, state: .ok))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UpcomingEntry>) -> Void) {
        let client = makeClient()
        Task {
            let next = Date().addingTimeInterval(30 * 60)
            do {
                async let e = client.fetchEvents(date: nil)
                async let t = client.fetchTasks()
                let entry = UpcomingEntry(date: .now, events: try await e, tasks: try await t, state: .ok)
                completion(Timeline(entries: [entry], policy: .after(next)))
            } catch LifeAPIError.notConfigured {
                completion(Timeline(entries: [UpcomingEntry(date: .now, events: [], tasks: [], state: .notConfigured)], policy: .after(next)))
            } catch {
                completion(Timeline(entries: [UpcomingEntry(date: .now, events: [], tasks: [], state: .failed)], policy: .after(next)))
            }
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
        StaticConfiguration(kind: "PRLifeUpcoming", provider: UpcomingProvider()) { entry in
            UpcomingWidgetView(entry: entry)
        }
        .configurationDisplayName("Upcoming")
        .description("Your next events and due tasks.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}
