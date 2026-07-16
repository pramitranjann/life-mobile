import WidgetKit
import SwiftUI
import PRLifeKit

private func timeText(_ date: Date?) -> String {
    guard let date else { return "" }
    let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
    return f.string(from: date)
}
private func priorityColor(_ p: LifeTaskPriority) -> Color {
    switch p { case .high: return Theme.danger; case .medium: return Theme.amber; case .low: return Theme.label }
}
private func eventTitle(_ e: LifeEvent) -> String { (e.title?.isEmpty == false ? e.title! : "Untitled") }
private func todayLocalDate() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
}

struct UpcomingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UpcomingEntry

    private var deepLink: URL? {
        switch entry.state {
        case .notConfigured: return URL(string: "prlife://settings")
        case .failed: return URL(string: "prlife://settings")
        default: return URL(string: "prlife://open")
        }
    }

    var body: some View {
        Group {
            switch entry.state {
            case .notConfigured: setup
            case .failed: failed
            default: content
            }
        }
        .containerBackground(Theme.bg, for: .widget)
        .widgetURL(deepLink)
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PR LIFE").font(Theme.mono(10, .medium)).foregroundStyle(Theme.accent)
            Text("Save API config in Devices").font(Theme.mono(11)).foregroundStyle(Theme.label)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding()
    }

    private var failed: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PR LIFE").font(Theme.mono(10, .medium)).foregroundStyle(Theme.accent)
            Text("Widget couldn't load").font(Theme.mono(11)).foregroundStyle(Theme.label)
            Text("Open Devices and resync").font(Theme.mono(10)).foregroundStyle(Theme.label.opacity(0.8))
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding()
    }

    @ViewBuilder private var content: some View {
        let nextEvents = LifeDashboard.nextEvents(entry.events, limit: family == .systemLarge ? 3 : 2)
        let today = todayLocalDate()
        let tasks = LifeDashboard.preferredTasks(entry.tasks, dueOn: today, limit: 3)
        let isShowingDueTodayTasks = entry.tasks.contains { $0.isDue(on: today) }
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
            medium(nextEvents, tasks, isShowingDueTodayTasks: isShowingDueTodayTasks)
        default:
            large(nextEvents, tasks, isShowingDueTodayTasks: isShowingDueTodayTasks)
        }
    }

    private func small(_ events: [LifeEvent]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("NEXT_").font(Theme.mono(10)).foregroundStyle(Theme.label)
            if let e = events.first {
                Text(eventTitle(e)).font(Theme.display(15)).foregroundStyle(Theme.text).lineLimit(2)
                Text(timeText(e.start)).font(Theme.mono(11)).foregroundStyle(Theme.accent).lineLimit(1)
            } else { Text("Clear").font(Theme.display(15)).foregroundStyle(Theme.text) }
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(14)
    }

    private func medium(_ events: [LifeEvent], _ tasks: [LifeTask], isShowingDueTodayTasks: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text("UPCOMING_").font(Theme.mono(10)).foregroundStyle(Theme.label)
                ForEach(events) { e in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(eventTitle(e)).font(Theme.body(12)).foregroundStyle(Theme.text).lineLimit(1)
                        Text(timeText(e.start)).font(Theme.mono(10)).foregroundStyle(Theme.accent).lineLimit(1)
                    }
                }
                Spacer()
            }
            Divider().overlay(Theme.hairline)
            VStack(alignment: .leading, spacing: 7) {
                Text(isShowingDueTodayTasks ? "DUE_" : "ACTIVE_").font(Theme.mono(10)).foregroundStyle(Theme.label)
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

    private func large(_ events: [LifeEvent], _ tasks: [LifeTask], isShowingDueTodayTasks: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EVENTS_").font(Theme.mono(10)).foregroundStyle(Theme.label)
            ForEach(events) { e in
                HStack(spacing: 8) {
                    Text(timeText(e.start)).font(Theme.mono(10)).foregroundStyle(Theme.accent)
                        .lineLimit(1).frame(width: 62, alignment: .leading)
                    Text(eventTitle(e)).font(Theme.body(13)).foregroundStyle(Theme.text).lineLimit(1)
                }
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
            Text(isShowingDueTodayTasks ? "DUE TODAY_" : "ACTIVE TASKS_").font(Theme.mono(10)).foregroundStyle(Theme.label)
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
