import PRLifeKit
import SwiftUI

struct TextCaptureComposer: View {
    let mode: MobileCaptureMode
    @Binding var content: String
    @Binding var context: CaptureContext
    @Binding var dueDate: Date?
    let isSaving: Bool
    let errorMessage: String?
    let onSave: () -> Void

    private var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if content.isEmpty {
                    Text(mode == .task ? "What needs doing?" : "Write a quick note…")
                        .font(Theme.body(16))
                        .foregroundStyle(Theme.label)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
                // 16pt minimum so iOS doesn't zoom the page on focus.
                TextEditor(text: $content)
                    .font(Theme.body(16))
                    .foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: mode == .task ? 62 : 92)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
            }
            .background(Theme.mutedBG)
            .overlay(Rectangle().stroke(Theme.border, lineWidth: 1))

            HStack(spacing: 8) {
                Menu {
                    ForEach(CaptureContext.allCases, id: \.self) { option in
                        Button {
                            context = option
                        } label: {
                            if context == option {
                                Label(option.displayName, systemImage: "checkmark")
                            } else {
                                Text(option.displayName)
                            }
                        }
                    }
                } label: {
                    composerControl(context.displayName.uppercased(), systemImage: "folder")
                }

                if mode == .task {
                    if dueDate == nil {
                        Button {
                            dueDate = Calendar.current.date(byAdding: .day, value: 1, to: .now)
                        } label: {
                            composerControl("ADD DUE DATE", systemImage: "calendar.badge.plus")
                        }
                        .buttonStyle(.pressable)
                    } else {
                        DatePicker(
                            "Due",
                            selection: Binding(get: { dueDate ?? .now }, set: { dueDate = $0 }),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .tint(Theme.accent)
                        .frame(minHeight: 44)
                    }
                }

                Spacer(minLength: 0)

                // Primary per the web `.life-btn.primary`: accent outline +
                // text, transparent bg — solid accent is only for live states.
                Button(action: onSave) {
                    Text(isSaving ? "SAVING_" : "SAVE_")
                        .font(Theme.mono(13, .medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .overlay(Rectangle().stroke(Theme.accent, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .disabled(trimmedContent.isEmpty || isSaving)
                .opacity(trimmedContent.isEmpty ? 0.45 : 1)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func composerControl(_ label: String, systemImage: String) -> some View {
        Label(label, systemImage: systemImage)
            .font(Theme.mono(12, .medium))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .overlay(Rectangle().stroke(Theme.accentLine, lineWidth: 1))
    }
}
