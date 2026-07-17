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
            QuickTextComposer(env: env, sync: sync)
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
                    ForEach(dueTasks.prefix(3)) { task in
                        TaskRow(task: task) { await sync.completeTask(id: task.id) }
                    }
                }
            }
            divider
            footer
        }
        .frame(width: 340)
        .background(Theme.bg)
        .task { await sync.refresh() }
        .onExitCommand { if env.isRecording { env.stopCapture() } }   // Esc stops an active capture
    }

    private var header: some View {
        HStack {
            Text("LIFE_").font(Theme.mono(14, .medium)).tracking(2).foregroundStyle(Theme.text)
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
                .buttonStyle(.pressable)
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
            }.buttonStyle(.pressable)
            Button { openWindow(id: "dashboard") } label: {
                Text("Dashboard").font(Theme.mono(11)).foregroundStyle(Theme.muted)
            }.buttonStyle(.pressable)
            Spacer()
            SettingsLink {
                Text("Settings").font(Theme.mono(11)).foregroundStyle(Theme.label)
            }.buttonStyle(.pressable)
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

private enum QuickTextMode: String, CaseIterable, Identifiable {
    case note = "Note"
    case task = "Task"

    var id: String { rawValue }
    var submitLabel: String {
        switch self {
        case .note: return "Add note"
        case .task: return "Add task"
        }
    }
    var placeholder: String {
        switch self {
        case .note: return "Write a quick note..."
        case .task: return "Add a task..."
        }
    }
}

struct QuickTextComposer: View {
    @ObservedObject var env: MacCaptureEnvironment
    @ObservedObject var sync: LifeSyncService
    var padded = true
    @State private var mode: QuickTextMode = .note
    @State private var text = ""
    @State private var isSaving = false
    @State private var message: String?
    @FocusState private var focused: Bool

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "QUICK ADD_")
                Spacer()
                QuickTextModeControl(mode: $mode)
            }

            QuickTextEditor(text: $text, placeholder: mode.placeholder, height: 70, focused: $focused)

            HStack(spacing: 8) {
                if let message {
                    Text(message)
                        .font(Theme.mono(10))
                        .foregroundStyle(message == "Saved" ? Theme.green : Theme.danger)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    submit()
                } label: {
                    QuickActionLabel(
                        title: isSaving ? "Saving..." : mode.submitLabel,
                        isEnabled: !trimmedText.isEmpty && !isSaving
                    )
                }
                .buttonStyle(.pressable)
                .disabled(trimmedText.isEmpty || isSaving)
            }
        }
        .padding(.horizontal, padded ? 16 : 0)
        .padding(.vertical, padded ? 14 : 0)
    }

    private func submit() {
        let value = trimmedText
        guard !value.isEmpty, !isSaving else { return }
        isSaving = true
        message = nil
        Task {
            do {
                switch mode {
                case .note:
                    try await env.createQuickNote(value)
                case .task:
                    try await env.createQuickTask(value)
                }
                await sync.refresh()
                text = ""
                message = "Saved"
            } catch {
                message = (error as? LocalizedError)?.errorDescription ?? "Save failed"
            }
            isSaving = false
        }
    }
}

private struct QuickTextModeControl: View {
    @Binding var mode: QuickTextMode

    var body: some View {
        // Neutral segmented control per the web `.segmented`: active item gets
        // panel-2 + brighter text — accent is reserved for primary actions.
        HStack(spacing: 2) {
            ForEach(QuickTextMode.allCases) { item in
                Button {
                    mode = item
                } label: {
                    Text(item.rawValue)
                        .font(Theme.mono(11, .medium))
                        .foregroundStyle(mode == item ? Theme.text : Theme.muted)
                        .frame(width: 54, height: 26)
                        .background(mode == item ? Theme.panel2 : Color.clear)
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(3)
        .background(Theme.mutedBG)
        .overlay(Rectangle().stroke(Theme.border, lineWidth: 1))
    }
}

struct QuickTextEditor: View {
    @Binding var text: String
    let placeholder: String
    var height: CGFloat
    @FocusState.Binding var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(Theme.body(13))
                .foregroundStyle(Theme.text)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .focused($focused)

            if text.isEmpty {
                Text(placeholder)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.label.opacity(0.72))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: height)
        .background(focused ? Theme.panel2 : Theme.panel)
        .overlay(Rectangle().stroke(focused ? Theme.accentLine.opacity(0.65) : Theme.border, lineWidth: 1))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(focused ? Theme.accent : Color.clear)
                .frame(width: 2)
        }
    }
}

struct QuickActionLabel: View {
    let title: String
    let isEnabled: Bool

    @State private var hovering = false

    // Web `.life-btn.primary`: accent border + text on transparent bg,
    // accent-soft fill only on hover.
    var body: some View {
        Text(title)
            .font(Theme.mono(11, .medium))
            .foregroundStyle(isEnabled ? Theme.accent : Theme.label)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(isEnabled && hovering ? Theme.accentSoft : Color.clear)
            .overlay(Rectangle().stroke(isEnabled ? Theme.accent : Theme.border, lineWidth: 1))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
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
                    .foregroundStyle(isQuick ? Theme.accentLine : Theme.label)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(isQuick || active ? Theme.accentSoft : Theme.panel)
            .overlay(Rectangle().stroke(isQuick || active ? Theme.accentLine : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }
}
