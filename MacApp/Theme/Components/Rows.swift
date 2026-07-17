import SwiftUI
import PRLifeKit

/// Event row: accent bar + title + time, with an optional countdown for the next event.
struct EventRow: View {
    let event: LifeEvent
    var isNext: Bool = false
    var dimmed: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AccentBar(color: isNext ? Theme.accent : Theme.border, height: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title ?? "Untitled")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(LifeFormatting.rangeLabel(for: event))
                        .font(Theme.mono(11))
                        .foregroundStyle(isNext ? Theme.accent : Theme.label)
                    if isNext, let mins = LifeFormatting.minutesUntil(event) {
                        Text(LifeFormatting.countdownLabel(minutes: mins))
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .opacity(dimmed ? 0.5 : 1)
    }
}

/// Task row: checkbox + title + priority dot + project label.
struct TaskRow: View {
    let task: LifeTask
    var checkboxSize: CGFloat = 18
    var onComplete: (() async -> Void)? = nil

    @State private var isCompleting = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            if let onComplete {
                Button {
                    guard !isCompleting else { return }
                    isCompleting = true
                    Task {
                        await onComplete()
                        // If the task survived (completion failed), uncheck.
                        isCompleting = false
                    }
                } label: {
                    TaskCheckbox(size: checkboxSize, isDone: isCompleting)
                        .contentShape(Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Complete \(task.title)")
            } else {
                TaskCheckbox(size: checkboxSize)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    PriorityDot(priority: task.priority)
                    if let project = task.projectSlug, !project.isEmpty {
                        Text(project.uppercased())
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.label)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
    }
}

/// Capture-history row: timestamp + status + duration + context.
struct CaptureRow: View {
    let record: CaptureRecord

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, HH:mm"
        return f
    }()
    private var timestamp: String { Self.timeFormatter.string(from: record.createdAt) }
    private var durationLabel: String {
        let total = Int(record.duration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
    private var statusColor: Color {
        switch record.status {
        case .done: return Theme.green
        case .failed: return Theme.danger
        default: return Theme.accent
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(timestamp)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text("\(record.status.rawValue.uppercased())_")
                    .font(Theme.mono(11, .medium))
                    .foregroundStyle(statusColor)
            }
            HStack(spacing: 6) {
                Text(durationLabel)
                Text("·")
                Text(record.context.displayName.uppercased())
            }
            .font(Theme.mono(11))
            .foregroundStyle(Theme.label)
        }
        .padding(.vertical, 12)
    }
}
