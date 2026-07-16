import SwiftUI
import PRLifeKit

/// Captures tab: local capture history from the SwiftData store.
struct CapturesView: View {
    @ObservedObject var env: MacCaptureEnvironment
    @ObservedObject var sync: LifeSyncService
    @State private var records: [CaptureRecord] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            QuickTextComposer(env: env, sync: sync)
                .padding(.horizontal, -16)
                .padding(.top, -14)
            Rectangle().fill(Theme.divider).frame(height: 1)
                .padding(.bottom, 14)
            HStack {
                SectionLabel(text: "CAPTURES_")
                Spacer()
                Text("\(records.count) total").font(Theme.mono(10)).foregroundStyle(Color(hex: "3A3A3A"))
            }
            .padding(.bottom, 8)

            if records.isEmpty {
                Text("No captures yet").font(Theme.body(13)).foregroundStyle(Theme.label)
                    .padding(.vertical, 16)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(records) { record in
                            EditableCaptureRow(record: record, env: env) {
                                reload()
                                Task { await sync.refresh() }
                            }
                            Rectangle().fill(Theme.divider).frame(height: 1)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .onAppear(perform: reload)
        .onReceive(env.objectWillChange) { _ in reload() }
    }

    private func reload() { records = env.store.all() }
}

private struct EditableCaptureRow: View {
    let record: CaptureRecord
    @ObservedObject var env: MacCaptureEnvironment
    var onSaved: () -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private var timestamp: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, HH:mm"
        return f.string(from: record.createdAt)
    }

    private var durationLabel: String {
        let total = Int(record.duration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var kindLabel: String {
        if record.serverEntryId?.hasPrefix("task:") == true { return "TASK_" }
        if record.audioFileName == nil { return "NOTE_" }
        return record.context.displayName.uppercased()
    }

    private var canEdit: Bool {
        record.transcript?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var statusColor: Color {
        switch record.status {
        case .done: return Theme.green
        case .failed: return Theme.danger
        default: return Theme.accent
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(timestamp)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text("\(record.status.rawValue.uppercased())_")
                    .font(Theme.mono(10, .medium))
                    .foregroundStyle(statusColor)
            }
            HStack(spacing: 6) {
                Text(durationLabel)
                Text(".")
                Text(kindLabel)
            }
            .font(Theme.mono(11))
            .foregroundStyle(Theme.label)

            if isEditing {
                QuickTextEditor(text: $draft, placeholder: "Edit capture...", height: 78, focused: $focused)
                HStack {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.danger)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Cancel") {
                        isEditing = false
                        errorMessage = nil
                    }
                    .buttonStyle(.plain)
                    .font(Theme.mono(11, .medium))
                    .foregroundStyle(Theme.label)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Theme.panel)
                    .overlay(Rectangle().stroke(Theme.border, lineWidth: 1))
                    Button {
                        save()
                    } label: {
                        QuickActionLabel(
                            title: isSaving ? "Saving..." : "Save",
                            isEnabled: !trimmedDraft.isEmpty && !isSaving
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmedDraft.isEmpty || isSaving)
                }
            } else {
                if let transcript = record.transcript, !transcript.isEmpty {
                    Text(transcript)
                        .font(Theme.body(12))
                        .foregroundStyle(Color(hex: "555555"))
                        .lineLimit(2)
                }
                if let error = record.lastError, !error.isEmpty {
                    Text(error)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.danger)
                        .lineLimit(2)
                }
                HStack {
                    Spacer()
                    Button("Edit") {
                        draft = record.transcript ?? ""
                        errorMessage = nil
                        isEditing = true
                        focused = true
                    }
                    .buttonStyle(.plain)
                    .font(Theme.mono(11, .medium))
                    .foregroundStyle(canEdit ? Theme.accent : Theme.label)
                    .disabled(!canEdit)
                }
            }
        }
        .padding(.vertical, 12)
    }

    private func save() {
        guard !trimmedDraft.isEmpty, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await env.updateTextCapture(id: record.id, content: trimmedDraft)
                isEditing = false
                onSaved()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Save failed"
            }
            isSaving = false
        }
    }
}
