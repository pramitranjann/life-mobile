import SwiftUI
import PRLifeKit

/// Today tab (Screen 5): date heading, 2-column Upcoming / Due Today, sync footer.
struct TodayView: View {
    @ObservedObject var sync: LifeSyncService
    private var today: String { LifeFormatting.todayLocalDate() }

    private var events: [LifeEvent] {
        (sync.snapshot?.events ?? []).sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }
    private var dueTasks: [LifeTask] {
        (sync.snapshot?.tasks ?? []).filter { $0.isDue(on: today) }
    }
    private var nextEventID: String? {
        events.first(where: { LifeFormatting.minutesUntil($0) != nil })?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
            HStack(alignment: .top, spacing: 20) {
                column(title: "UPCOMING_") {
                    if events.isEmpty { empty("No events today") }
                    else {
                        ForEach(events) { event in
                            EventRow(event: event, isNext: event.id == nextEventID)
                            divider
                        }
                    }
                }
                column(title: "DUE TODAY_") {
                    if dueTasks.isEmpty { empty("Nothing due today") }
                    else {
                        ForEach(dueTasks) { task in
                            TaskRow(task: task, checkboxSize: 13)
                            divider
                        }
                    }
                }
            }
            Spacer(minLength: 12)
            syncFooter
        }
        .padding(20)
    }

    private var heading: some View {
        let parts = LifeFormatting.headingParts()
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(parts.weekday).font(Theme.display(22)).foregroundStyle(Theme.text)
            Text(parts.date).font(Theme.mono(11)).foregroundStyle(Theme.label)
        }
        .padding(.bottom, 18)
    }

    private func column<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: title)
                .padding(.bottom, 12)
                .overlay(Rectangle().fill(Theme.hairline).frame(height: 1), alignment: .bottom)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var syncFooter: some View {
        HStack {
            switch sync.state {
            case .synced(let date):
                SyncDot(color: Theme.green, text: "Connected · synced \(relative(date))")
            case .syncing:
                SyncDot(color: Theme.amber, text: "Syncing…")
            case .failed:
                SyncDot(color: Theme.danger, text: "Disconnected")
            case .idle:
                SyncDot(color: Theme.label, text: "Not synced")
            }
            Spacer()
            Button { Task { await sync.refresh() } } label: {
                Text("Sync now →").font(Theme.mono(10)).foregroundStyle(Color(hex: "3A3A3A"))
            }.buttonStyle(.plain)
        }
        .padding(.top, 12)
        .overlay(Rectangle().fill(Theme.hairline).frame(height: 1), alignment: .top)
    }

    private func empty(_ text: String) -> some View {
        Text(text).font(Theme.body(13)).foregroundStyle(Theme.label).padding(.vertical, 11)
    }
    private var divider: some View { Rectangle().fill(Theme.divider).frame(height: 1) }

    private func relative(_ date: Date) -> String {
        let mins = Int(Date().timeIntervalSince(date) / 60)
        if mins <= 0 { return "just now" }
        if mins < 60 { return "\(mins)m ago" }
        return "\(mins / 60)h ago"
    }
}
