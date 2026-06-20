import WidgetKit
import SwiftUI
import PRLifeKit

private func timeText(_ date: Date?) -> String {
    guard let date else { return "" }
    let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
}
private func priorityColor(_ p: LifeTaskPriority) -> Color {
    switch p { case .high: return Theme.danger; case .medium: return Theme.amber; case .low: return Theme.label }
}
private func eventTitle(_ e: LifeEvent) -> String { (e.title?.isEmpty == false ? e.title! : "Untitled") }

struct UpcomingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UpcomingEntry

    var body: some View {
        switch entry.state {
        case .notConfigured: setup
        case .failed where entry.events.isEmpty && entry.tasks.isEmpty: setup
        default: content
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PR LIFE").font(Theme.mono(10, .medium)).foregroundStyle(Theme.accent)
            Text("Set up in the app").font(Theme.mono(11)).foregroundStyle(Theme.label)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding()
    }

    @ViewBuilder private var content: some View {
        let nextEvents = LifeDashboard.nextEvents(entry.events, limit: family == .systemLarge ? 3 : 2)
        let tasks = LifeDashboard.topTasks(entry.tasks, limit: 3)
        switch family {
        case .accessoryInline:
            Text(nextEvents.first.map { "\(timeText($0.start)) \(eventTitle($0))" } ?? "No events")
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("NEXT").font(.system(size: 10, weight: .medium))
                if let e = nextEvents.first {
                    Text(eventTitle(e)).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(timeText(e.start)).font(.system(size: 12))
                } else { Text("No upcoming events").font(.system(size: 12)) }
            }
        case .systemSmall:
            small(nextEvents)
        case .systemMedium:
            medium(nextEvents, tasks)
        default:
            large(nextEvents, tasks)
        }
    }

    private func small(_ events: [LifeEvent]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("NEXT_").font(Theme.mono(10)).foregroundStyle(Theme.label)
            if let e = events.first {
                Text(eventTitle(e)).font(Theme.display(15)).foregroundStyle(Theme.text).lineLimit(2)
                Text(timeText(e.start)).font(Theme.mono(11)).foregroundStyle(Theme.accent)
            } else { Text("Clear").font(Theme.display(15)).foregroundStyle(Theme.text) }
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(14)
    }

    private func medium(_ events: [LifeEvent], _ tasks: [LifeTask]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text("UPCOMING_").font(Theme.mono(10)).foregroundStyle(Theme.label)
                ForEach(events) { e in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(eventTitle(e)).font(Theme.body(12)).foregroundStyle(Theme.text).lineLimit(1)
                        Text(timeText(e.start)).font(Theme.mono(10)).foregroundStyle(Theme.accent)
                    }
                }
                Spacer()
            }
            Divider().overlay(Theme.hairline)
            VStack(alignment: .leading, spacing: 7) {
                Text("DUE_").font(Theme.mono(10)).foregroundStyle(Theme.label)
                ForEach(tasks) { t in
                    HStack(spacing: 6) {
                        Circle().fill(priorityColor(t.priority)).frame(width: 5, height: 5)
                        Text(t.title).font(Theme.body(12)).foregroundStyle(Theme.text).lineLimit(1)
                    }
                }
                Spacer()
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(14)
    }

    private func large(_ events: [LifeEvent], _ tasks: [LifeTask]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EVENTS_").font(Theme.mono(10)).foregroundStyle(Theme.label)
            ForEach(events) { e in
                HStack(spacing: 8) {
                    Text(timeText(e.start)).font(Theme.mono(10)).foregroundStyle(Theme.accent).frame(width: 40, alignment: .leading)
                    Text(eventTitle(e)).font(Theme.body(13)).foregroundStyle(Theme.text).lineLimit(1)
                }
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
            Text("DUE TODAY_").font(Theme.mono(10)).foregroundStyle(Theme.label)
            ForEach(tasks) { t in
                HStack(spacing: 8) {
                    Circle().fill(priorityColor(t.priority)).frame(width: 6, height: 6)
                    Text(t.title).font(Theme.body(13)).foregroundStyle(Theme.text).lineLimit(1)
                }
            }
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(16)
    }
}
