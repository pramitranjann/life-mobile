import SwiftUI
import PRLifeKit

struct CaptureRow: View {
    let record: CaptureRecord
    let isDeleting: Bool
    let onEdit: (() -> Void)?
    let onResume: (() -> Void)?
    let onRetry: (() -> Void)?
    let onDiscard: (() -> Void)?

    private var timeText: String {
        let f = DateFormatter(); f.dateFormat = "EEE, HH:mm"; return f.string(from: record.createdAt)
    }
    private var durationText: String {
        String(format: "%d:%02d", Int(record.duration) / 60, Int(record.duration) % 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(timeText).font(Theme.body(14)).foregroundStyle(Theme.text)
                Spacer()
                StatusBadge(status: record.status)
            }
            HStack(spacing: 6) {
                Text(durationText).font(Theme.mono(11)).foregroundStyle(Theme.label)
                Text("·").foregroundStyle(Theme.label)
                Text(record.mode.badgeLabel).font(Theme.mono(10, .medium)).foregroundStyle(Theme.accent)
                Text("·").foregroundStyle(Theme.label)
                Text((record.projectSlug ?? record.context.displayName).uppercased())
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.label)
                if let routeName = record.inputRoute?.name {
                    Text("·").foregroundStyle(Theme.label)
                    Text(routeName.uppercased())
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.label)
                        .lineLimit(1)
                }
            }
            if let t = record.transcript, !t.isEmpty {
                Text(t).font(Theme.body(12)).foregroundStyle(Color(hex: "555555")).lineLimit(1)
            }
            if let error = record.lastError, !error.isEmpty {
                Text(error)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.danger)
                    .lineLimit(2)
            }
            if let recoveryReason = record.recoveryReason {
                Text(recoveryReason.message)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if onEdit != nil || onResume != nil || onRetry != nil || onDiscard != nil {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 82), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    if let onEdit {
                        recoveryButton("EDIT_", action: onEdit)
                    }
                    if let onResume {
                        recoveryButton("RESUME_", action: onResume)
                    }
                    if let onRetry {
                        recoveryButton("RETRY_", action: onRetry)
                    }
                    if let onDiscard {
                        recoveryButton("DISCARD_", color: Theme.danger, action: onDiscard)
                    }
                }
            }
            if record.status == .processing || record.status == .uploading {
                Rectangle().fill(Theme.accent).frame(height: 2)
            }
            if isDeleting {
                Text("DELETING_")
                    .font(Theme.mono(10, .medium))
                    .foregroundStyle(Theme.label)
            }
        }
        .padding(.vertical, 15).padding(.horizontal, 20)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.hairline), alignment: .top)
    }

    private func recoveryButton(
        _ label: String,
        color: Color = Theme.accent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(Theme.mono(10, .medium))
                .foregroundStyle(color)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
                .overlay(Rectangle().stroke(color.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
