import SwiftUI
import WidgetKit
import PRLifeKit

/// Shared data shaping for all widget families.
private struct WidgetData {
    let events: [LifeEvent]
    let dueTasks: [LifeTask]
    let nextEventID: String?

    init(_ snapshot: LifeSnapshot?) {
        let today = LifeFormatting.todayLocalDate()
        events = (snapshot?.events ?? [])
            .sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
        dueTasks = (snapshot?.tasks ?? []).filter { $0.isDue(on: today) }
        nextEventID = events.first(where: { LifeFormatting.minutesUntil($0) != nil })?.id
    }
}

struct LifeWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LifeEntry

    private var data: WidgetData { WidgetData(entry.snapshot) }

    var body: some View {
        Group {
            switch family {
            case .systemSmall: smallBody
            case .systemLarge: largeBody
            default: mediumBody
            }
        }
        .containerBackground(Theme.bg, for: .widget)
    }

    // MARK: Small
    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PR_").font(Theme.mono(10, .medium)).tracking(1).foregroundStyle(Theme.accent)
                Spacer()
                Circle().fill(Theme.green).frame(width: 6, height: 6)
            }
            Spacer()
            if let next = data.events.first {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEXT_").font(Theme.mono(10)).tracking(1).foregroundStyle(Theme.label)
                    Text(next.title ?? "Untitled").font(Theme.display(14)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(timeLine(next)).font(Theme.mono(11)).foregroundStyle(Theme.accent)
                }
            } else {
                Text("No events").font(Theme.body(13)).foregroundStyle(Theme.label)
            }
            Spacer()
            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.bottom, 8)
            Text(dayLabel().uppercased()).font(Theme.mono(10)).tracking(0.8).foregroundStyle(Theme.label)
        }
    }

    // MARK: Medium
    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LifeFormatting.headingParts().weekday).font(Theme.display(18)).foregroundStyle(Theme.text)
                    Text(dayLabel().uppercased()).font(Theme.mono(10)).foregroundStyle(Theme.label)
                }
                Spacer()
                Text("LIFE_").font(Theme.mono(10, .medium)).foregroundStyle(Theme.accent)
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(data.events.prefix(2)) { event in
                        eventLine(event, dim: event.id != data.nextEventID)
                    }
                    if data.events.isEmpty { Text("No events").font(Theme.body(11)).foregroundStyle(Theme.label) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(data.dueTasks.prefix(3).enumerated()), id: \.element.id) { idx, task in
                        taskLine(task, opacity: idx == 0 ? 1 : (idx == 1 ? 0.6 : 0.35))
                    }
                    if data.dueTasks.isEmpty { Text("Nothing due").font(Theme.body(11)).foregroundStyle(Theme.label) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .overlay(Rectangle().fill(Theme.hairline).frame(width: 1), alignment: .leading)
            }
        }
    }

    // MARK: Large
    private var largeBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LifeFormatting.headingParts().weekday).font(Theme.display(20)).foregroundStyle(Theme.text)
                    Text(LifeFormatting.headingParts().date).font(Theme.mono(10)).tracking(1).foregroundStyle(Theme.label)
                }
                Spacer()
                HStack(spacing: 6) {
                    Text("PR LIFE_").font(Theme.mono(10, .medium)).foregroundStyle(Theme.accent)
                    Circle().fill(Theme.green).frame(width: 6, height: 6)
                }
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
            sectionLabel("EVENTS_")
            ForEach(data.events.prefix(3)) { event in
                eventLine(event, dim: event.id != data.nextEventID)
            }
            if data.events.isEmpty { Text("No events").font(Theme.body(12)).foregroundStyle(Theme.label) }
            Rectangle().fill(Theme.hairline).frame(height: 1)
            sectionLabel("DUE TODAY_")
            ForEach(data.dueTasks.prefix(3)) { task in
                taskLine(task, opacity: 1)
            }
            if data.dueTasks.isEmpty { Text("Nothing due").font(Theme.body(12)).foregroundStyle(Theme.label) }
            Spacer(minLength: 0)
        }
    }

    // MARK: Shared bits
    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(Theme.mono(10)).tracking(1).foregroundStyle(Theme.label)
    }

    private func eventLine(_ event: LifeEvent, dim: Bool) -> some View {
        HStack(spacing: 7) {
            Rectangle().fill(event.id == data.nextEventID ? Theme.accent : Theme.border).frame(width: 2, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title ?? "Untitled").font(Theme.body(12)).foregroundStyle(Theme.text).lineLimit(1)
                Text(timeLine(event)).font(Theme.mono(10))
                    .foregroundStyle(event.id == data.nextEventID ? Theme.accent : Theme.label)
            }
            Spacer(minLength: 0)
        }
        .opacity(dim ? 0.55 : 1)
    }

    private func taskLine(_ task: LifeTask, opacity: Double) -> some View {
        HStack(spacing: 7) {
            Rectangle().stroke(Color(hex: "2E2E2E"), lineWidth: 1).frame(width: 11, height: 11)
            Text(task.title).font(Theme.body(12)).foregroundStyle(Theme.text).lineLimit(1)
            Spacer(minLength: 0)
            Circle().fill(Theme.priorityColor(task.priority)).frame(width: 5, height: 5)
        }
        .opacity(opacity)
    }

    private func timeLine(_ event: LifeEvent) -> String {
        let base = LifeFormatting.timeLabel(for: event)
        if event.id == data.nextEventID, let mins = LifeFormatting.minutesUntil(event) {
            return "\(base) · \(LifeFormatting.countdownLabel(minutes: mins))"
        }
        return base
    }

    private func dayLabel() -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE · d MMM"
        return f.string(from: Date())
    }
}
