import SwiftUI
import PRLifeKit

/// The 340pt menu-bar popover (CODEX_PROMPT Screen 4): header, Quick Capture grid,
/// today's upcoming events, due-today tasks, footer.
struct MenuBarPopover: View {
    @ObservedObject var env: MacCaptureEnvironment
    @ObservedObject var sync: LifeSyncService
    @Environment(\.openWindow) private var openWindow

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
        VStack(spacing: 0) {
            header
            syncErrorBanner
            divider
            QuickCaptureGrid(env: env)
            divider
            if env.isRecording {
                recordingBanner
                divider
            }
            section(title: "UPCOMING_") {
                if events.isEmpty { emptyText("No events today") }
                else {
                    ForEach(events.prefix(3)) { event in
                        EventRow(event: event, isNext: event.id == nextEventID)
                    }
                }
            }
            divider
            section(title: "DUE TODAY_") {
                if dueTasks.isEmpty { emptyText("Nothing due today") }
                else {
                    ForEach(dueTasks.prefix(3)) { TaskRow(task: $0) }
                }
            }
            divider
            footer
        }
        .frame(width: 340)
        .background(Color(hex: "0F0F0F"))
        .task { await sync.refresh() }
        .onExitCommand { if env.isRecording { env.stopCapture() } }   // Esc stops an active capture
    }

    private var header: some View {
        HStack {
            Text("LIFE_").font(Theme.mono(12, .medium)).tracking(1.2).foregroundStyle(Theme.text)
            Spacer()
            syncStatus
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var syncStatus: some View {
        switch sync.state {
        case .idle:
            return AnyView(SyncDot(color: Theme.label, text: "IDLE"))
        case .syncing:
            return AnyView(SyncDot(color: Theme.amber, text: "SYNCING…"))
        case .synced(let date):
            return AnyView(SyncDot(color: Theme.green, text: "SYNCED · \(relative(date))"))
        case .failed:
            return AnyView(SyncDot(color: Theme.danger, text: "OFFLINE"))
        }
    }

    /// Visible only when a sync failed — shows the actual reason (config / network / auth).
    @ViewBuilder private var syncErrorBanner: some View {
        if case .failed(let message) = sync.state {
            Text(message)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Theme.danger.opacity(0.08))
        }
    }

    private var recordingBanner: some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.accent).frame(width: 7, height: 7)
            Text("Recording \(env.recordingContext?.displayName ?? "")…")
                .font(Theme.body(13)).foregroundStyle(Theme.accent)
            Spacer()
            Button("Stop") { env.stopCapture() }
                .buttonStyle(.plain)
                .font(Theme.mono(11, .medium))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.accentSoft)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button { openWeb() } label: {
                Text("Open PR Life →").font(Theme.mono(11, .medium)).foregroundStyle(Theme.accent)
            }.buttonStyle(.plain)
            Button { openWindow(id: "dashboard") } label: {
                Text("Dashboard").font(Theme.mono(11)).foregroundStyle(Theme.muted)
            }.buttonStyle(.plain)
            Spacer()
            SettingsLink {
                Text("Settings").font(Theme.mono(11)).foregroundStyle(Theme.label)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(text: title).padding(.bottom, 4)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private func emptyText(_ text: String) -> some View {
        Text(text).font(Theme.body(12)).foregroundStyle(Theme.label).padding(.vertical, 6)
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
    }

    private func relative(_ date: Date) -> String {
        let mins = Int(Date().timeIntervalSince(date) / 60)
        if mins <= 0 { return "now" }
        if mins < 60 { return "\(mins)m ago" }
        return "\(mins / 60)h ago"
    }

    private func openWeb() {
        let base = KeychainConfig.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = URL(string: base.isEmpty ? "https://" : base)?.appendingPathComponent("life") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// 2×2 Quick Capture grid wired to the capture environment.
struct QuickCaptureGrid: View {
    @ObservedObject var env: MacCaptureEnvironment

    private let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
    private let cells: [(CaptureContext, String, String)] = [
        (.work, "Work_", "⌃⌥W"),
        (.ideas, "Ideas_", "⌃⌥I"),
        (.journal, "Journal_", "⌃⌥J"),
        (.quick, "Quick_", "⌃⌥⎵"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "QUICK CAPTURE_")
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(cells, id: \.0) { context, label, hint in
                    captureButton(context: context, label: label, hint: hint)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private func captureButton(context: CaptureContext, label: String, hint: String) -> some View {
        let isQuick = context == .quick
        let active = env.isRecording && env.recordingContext == context
        return Button { env.toggleCapture(context) } label: {
            HStack(spacing: 6) {
                Circle().fill(Theme.accent).frame(width: 5, height: 5)
                Text(label).font(Theme.mono(11, .medium))
                    .foregroundStyle(isQuick || active ? Theme.accent : Theme.text)
                Spacer(minLength: 0)
                Text(hint).font(Theme.mono(10))
                    .foregroundStyle(isQuick ? Theme.accent.opacity(0.45) : Color(hex: "3A3A3A"))
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(isQuick || active ? Theme.accentSoft : Theme.panel)
            .overlay(Rectangle().stroke(isQuick || active ? Theme.accentLine : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
