import WidgetKit
import SwiftUI
import PRLifeKit

private enum UpcomingWidgetFormatting {
    static func timeLabel(for event: LifeEvent) -> String {
        if event.allDay { return "All day" }
        guard let start = event.start else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: start)
    }

    static func minutesUntil(_ event: LifeEvent, now: Date = Date()) -> Int? {
        guard let start = event.start else { return nil }
        let seconds = start.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        return Int(seconds / 60)
    }

    static func countdownLabel(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    static func weekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
}

private struct UpcomingWidgetData {
    let events: [LifeEvent]
    let tasks: [LifeTask]
    let isShowingDueTodayTasks: Bool
    let nextEventID: String?

    init(entry: UpcomingEntry) {
        let today = LifeLocalDate.current()
        events = LifeDashboard.nextEvents(entry.events, limit: 3)
        isShowingDueTodayTasks = entry.tasks.contains { $0.isDue(on: today) }
        tasks = LifeDashboard.preferredTasks(entry.tasks, dueOn: today, limit: 3)
        nextEventID = events.first(where: { UpcomingWidgetFormatting.minutesUntil($0) != nil })?.id
    }
}

private func eventTitle(_ event: LifeEvent) -> String {
    event.title?.isEmpty == false ? event.title! : "Untitled"
}

private func priorityColor(_ priority: LifeTaskPriority) -> Color {
    switch priority {
    case .high: return Theme.danger
    case .medium: return Theme.amber
    case .low: return Theme.label
    }
}

struct UpcomingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UpcomingEntry

    private var data: UpcomingWidgetData { UpcomingWidgetData(entry: entry) }
    private var deepLink: URL? {
        switch entry.state {
        case .notConfigured, .failed: return URL(string: "prlife://settings")
        case .ok: return URL(string: "prlife://open")
        }
    }

    var body: some View {
        Group {
            switch entry.state {
            case .notConfigured: stateView(title: "SETUP_", message: "Save API config in Devices")
            case .failed: stateView(title: "OFFLINE_", message: "Open Devices and resync")
            case .ok: content
            }
        }
        .containerBackground(Theme.bg, for: .widget)
        .widgetURL(deepLink)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            accessoryInlineBody
        case .accessoryRectangular:
            accessoryRectangularBody
        case .systemSmall:
            smallBody
        case .systemMedium:
            mediumBody
        default:
            largeBody
        }
    }

    // MARK: - Home Screen

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PR_")
                    .font(Theme.mono(10, .medium))
                    .tracking(1)
                    .foregroundStyle(Theme.accent)
                Spacer()
                statusDot
            }

            Spacer()

            if let next = data.events.first {
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel("NEXT_")
                    Text(eventTitle(next))
                        .font(Theme.display(14))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                    Text(timeLine(next))
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                }
            } else if let task = data.tasks.first {
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel(data.isShowingDueTodayTasks ? "DUE_" : "TASK_")
                    Text(task.title)
                        .font(Theme.display(14))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(priorityColor(task.priority))
                            .frame(width: 5, height: 5)
                        Text(data.isShowingDueTodayTasks ? "Today" : "Active")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.accent)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel("CLEAR_")
                    Text("No active tasks")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.label)
                }
            }

            Spacer()

            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
                .padding(.bottom, 8)
            Text(dayLabel().uppercased())
                .font(Theme.mono(10))
                .tracking(0.8)
                .foregroundStyle(Theme.label)
        }
    }

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            widgetHeader(titleSize: 18, compactBrand: true)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(data.events.prefix(2)) { event in
                        eventLine(event, dim: event.id != data.nextEventID)
                    }
                    if data.events.isEmpty {
                        emptyLabel("No events")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(data.tasks.prefix(3).enumerated()), id: \.element.id) { index, task in
                        taskLine(task, opacity: taskOpacity(at: index))
                    }
                    if data.tasks.isEmpty {
                        emptyLabel("No active tasks")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .overlay(Rectangle().fill(Theme.hairline).frame(width: 1), alignment: .leading)
            }
        }
    }

    private var largeBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            widgetHeader(titleSize: 20, compactBrand: false)

            Rectangle().fill(Theme.hairline).frame(height: 1)
            sectionLabel("EVENTS_")
            ForEach(data.events.prefix(3)) { event in
                eventLine(event, dim: event.id != data.nextEventID)
            }
            if data.events.isEmpty {
                emptyLabel("No events")
            }

            Rectangle().fill(Theme.hairline).frame(height: 1)
            sectionLabel(data.isShowingDueTodayTasks ? "DUE TODAY_" : "ACTIVE TASKS_")
            ForEach(data.tasks.prefix(3)) { task in
                taskLine(task, opacity: 1)
            }
            if data.tasks.isEmpty {
                emptyLabel("No active tasks")
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Lock Screen

    private var accessoryInlineBody: some View {
        Text(data.events.first.map { "\(UpcomingWidgetFormatting.timeLabel(for: $0)) \(eventTitle($0))" } ?? "PR Life · Clear")
    }

    private var accessoryRectangularBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("NEXT_")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
            if let next = data.events.first {
                Text(eventTitle(next))
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(timeLine(next))
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
            } else {
                Text("No upcoming events")
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
        }
    }

    // MARK: - States

    @ViewBuilder
    private func stateView(title: String, message: String) -> some View {
        if family == .accessoryInline {
            Text("PR Life · \(message)")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("PR LIFE_")
                        .font(Theme.mono(10, .medium))
                        .tracking(1)
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Circle()
                        .stroke(Theme.label, lineWidth: 1)
                        .frame(width: 6, height: 6)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 5) {
                    sectionLabel(title)
                    Text(message)
                        .font(Theme.body(family == .systemSmall ? 12 : 13))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                }
            }
        }
    }

    // MARK: - Shared Components

    private var statusDot: some View {
        Circle()
            .fill(Theme.green)
            .frame(width: 6, height: 6)
            .accessibilityLabel("Synced")
    }

    private func widgetHeader(titleSize: CGFloat, compactBrand: Bool) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(UpcomingWidgetFormatting.weekday(entry.date))
                    .font(Theme.display(titleSize))
                    .foregroundStyle(Theme.text)
                Text(dayLabel().uppercased())
                    .font(Theme.mono(10))
                    .tracking(compactBrand ? 0 : 1)
                    .foregroundStyle(Theme.label)
            }
            Spacer()
            HStack(spacing: 6) {
                Text(compactBrand ? "LIFE_" : "PR LIFE_")
                    .font(Theme.mono(10, .medium))
                    .foregroundStyle(Theme.accent)
                if !compactBrand {
                    statusDot
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.mono(10))
            .tracking(1)
            .foregroundStyle(Theme.label)
    }

    private func emptyLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.body(11))
            .foregroundStyle(Theme.label)
            .lineLimit(1)
    }

    private func eventLine(_ event: LifeEvent, dim: Bool) -> some View {
        HStack(spacing: 7) {
            Rectangle()
                .fill(event.id == data.nextEventID ? Theme.accent : Theme.border)
                .frame(width: 2, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(eventTitle(event))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(timeLine(event))
                    .font(Theme.mono(10))
                    .foregroundStyle(event.id == data.nextEventID ? Theme.accent : Theme.label)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .opacity(dim ? 0.55 : 1)
    }

    private func taskLine(_ task: LifeTask, opacity: Double) -> some View {
        HStack(spacing: 7) {
            Rectangle()
                .stroke(Theme.border, lineWidth: 1)
                .frame(width: 11, height: 11)
            Text(task.title)
                .font(Theme.body(12))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 0)
            Circle()
                .fill(priorityColor(task.priority))
                .frame(width: 5, height: 5)
        }
        .opacity(opacity)
    }

    private func taskOpacity(at index: Int) -> Double {
        switch index {
        case 0: return 1
        case 1: return 0.6
        default: return 0.35
        }
    }

    private func timeLine(_ event: LifeEvent) -> String {
        let base = UpcomingWidgetFormatting.timeLabel(for: event)
        if event.id == data.nextEventID, let minutes = UpcomingWidgetFormatting.minutesUntil(event) {
            return "\(base) · \(UpcomingWidgetFormatting.countdownLabel(minutes: minutes))"
        }
        return base
    }

    private func dayLabel() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE · d MMM"
        return formatter.string(from: entry.date)
    }
}
