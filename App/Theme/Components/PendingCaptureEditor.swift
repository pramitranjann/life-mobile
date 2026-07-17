import PRLifeKit
import SwiftUI

struct PendingCaptureEditor: View {
    let record: CaptureRecord
    let isSaving: Bool
    let errorMessage: String?
    let onSave: (String, CaptureContext) -> Void
    let onRetry: () -> Void
    let onDiscard: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var transcript: String
    @State private var context: CaptureContext

    init(
        record: CaptureRecord,
        isSaving: Bool,
        errorMessage: String?,
        onSave: @escaping (String, CaptureContext) -> Void,
        onRetry: @escaping () -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.record = record
        self.isSaving = isSaving
        self.errorMessage = errorMessage
        self.onSave = onSave
        self.onRetry = onRetry
        self.onDiscard = onDiscard
        _transcript = State(initialValue: record.transcript ?? "")
        _context = State(initialValue: record.context)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                // 16pt minimum so iOS doesn't zoom the page on focus.
                TextEditor(text: $transcript)
                    .font(Theme.body(16))
                    .foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 180)
                    .background(Theme.mutedBG)
                    .overlay(Rectangle().stroke(Theme.border, lineWidth: 1))

                Menu {
                    ForEach(CaptureContext.allCases, id: \.self) { option in
                        Button(option.displayName) { context = option }
                    }
                } label: {
                    Label(context.displayName.uppercased(), systemImage: "folder")
                        .font(Theme.mono(12, .medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .overlay(Rectangle().stroke(Theme.accentLine, lineWidth: 1))
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    action("DISCARD_", color: Theme.danger, action: onDiscard)
                    if record.canRetry {
                        action("RETRY_", color: Theme.amber, action: onRetry)
                    }
                    action("SAVE_", color: Theme.accent) {
                        onSave(transcript.trimmingCharacters(in: .whitespacesAndNewlines), context)
                    }
                    .disabled(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .disabled(isSaving)

                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("REVIEW CAPTURE_")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func action(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Theme.mono(12, .medium))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
                .overlay(Rectangle().stroke(color.opacity(PRLifeTokens.Alpha.accentLine), lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }
}
