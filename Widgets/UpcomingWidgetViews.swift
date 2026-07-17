import WidgetKit
import SwiftUI
import PRLifeKit

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
        nextEventID = events.first(where: { LifeFormatting.minutesUntil($0) != nil })?.id
    }
}

private func eventTitle(_ event: LifeEvent) -> String {
    event.title?.isEmpty == false ? event.title! : "Untitled"
}

struct UpcomingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UpcomingEntry

    private var data: UpcomingWidgetData { UpcomingWidgetData(entry: entry) }
    private var freshnessLabel: String? {
        guard entry.state.showsCachedContent, let generatedAt = entry.generatedAt else { return nil }
        return LifeSnapshotAge(generatedAt: generatedAt, now: entry.date).label
    }
    private var deepLink: URL? {
        switch entry.state {
        case .configurationRequired, .authenticationRequired, .temporaryFailure:
            return LifeDeepLink.settings
        case .current, .cachedAfterTemporaryFailure:
            // A plain tap only opens the app. The web app opens exclusively
            // via the WEB_ action.
            return LifeDeepLink.home
        }
    }

    var body: some View {
        Group {
            switch entry.state {
            case .configurationRequired:
                stateView(title: "SETUP_", message: "Save API config in Settings")
            case .authenticationRequired:
                stateView(title: "SIGN IN_", message: "API access needs attention")
            case .temporaryFailure:
                stateView(title: "OFFLINE_", message: "No saved widget data yet")
            case .current, .cachedAfterTemporaryFailure:
                content
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
                        PriorityDot(priority: task.priority)
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
            Text(freshnessLabel ?? dayLabel().uppercased())
                .font(Theme.mono(10))
                .tracking(freshnessLabel == nil ? 0.8 : 0.2)
                .foregroundStyle(freshnessLabel == nil ? Theme.label : Theme.amber)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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

            // Links, not Button(intent:) — these actions just open the app at a
            // deep link, and OpenURLIntent from widget buttons is unreliable.
            HStack(spacing: 8) {
                Link(destination: LifeDeepLink.capture()) {
                    actionLabel("CAPTURE_", systemImage: "waveform")
                }
                Link(destination: LifeDeepLink.note) {
                    actionLabel("NOTE_", systemImage: "note.text.badge.plus")
                }
                Link(destination: LifeDeepLink.web(.calendar(eventID: data.events.first?.id))) {
                    actionLabel("WEB_", systemImage: "arrow.up.right")
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Lock Screen

    private var accessoryInlineBody: some View {
        let content = data.events.first.map {
            "\(LifeFormatting.timeLabel(for: $0)) \(eventTitle($0))"
        } ?? "PR Life · Clear"
        return Text(freshnessLabel.map { "\($0) · \(content)" } ?? content)
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
            if let freshnessLabel {
                Text(freshnessLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
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
            .fill(entry.state.showsCachedContent ? Theme.amber : Theme.green)
            .frame(width: 6, height: 6)
            .accessibilityLabel(entry.state.showsCachedContent ? "Showing saved data" : "Synced")
    }

    private func widgetHeader(titleSize: CGFloat, compactBrand: Bool) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LifeFormatting.headingParts(entry.date).weekday)
                    .font(Theme.display(titleSize))
                    .foregroundStyle(Theme.text)
                Text(dayLabel().uppercased())
                    .font(Theme.mono(10))
                    .tracking(compactBrand ? 0 : 1)
                    .foregroundStyle(Theme.label)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 6) {
                    Text(compactBrand ? "LIFE_" : "PR LIFE_")
                        .font(Theme.mono(10, .medium))
                        .foregroundStyle(Theme.accent)
                    if !compactBrand {
                        statusDot
                    }
                }
                if let freshnessLabel {
                    Text(freshnessLabel)
                        .font(Theme.mono(10, .medium))
                        .foregroundStyle(Theme.amber)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
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

    /// Square accent-outline action per the web primary button (transparent bg,
    /// accent border + text) — never the system's default tinted capsule.
    private func actionLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(Theme.mono(11, .medium))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, minHeight: 30)
            .overlay(Rectangle().stroke(Theme.accentLine, lineWidth: 1))
    }

    private func emptyLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.body(11))
            .foregroundStyle(Theme.label)
            .lineLimit(1)
    }

    // Rows are display-only: tapping them falls through to the widget's own
    // deep link (open the app). Only WEB_ ever leaves for the web app.
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
            Button(intent: CompleteWidgetTaskIntent(taskID: task.id)) {
                TaskCheckbox(size: 18)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(task.title)")

            Text(task.title)
                .font(Theme.body(12))
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            Spacer(minLength: 0)
            PriorityDot(priority: task.priority)
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
        let base = LifeFormatting.timeLabel(for: event)
        if event.id == data.nextEventID, let minutes = LifeFormatting.minutesUntil(event) {
            return "\(base) · \(LifeFormatting.countdownLabel(minutes: minutes))"
        }
        return base
    }

    private func dayLabel() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE · d MMM"
        return formatter.string(from: entry.date)
    }
}
