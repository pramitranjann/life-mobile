import SwiftUI
import PRLifeKit

/// DM Mono uppercase label with a trailing underscore, e.g. `UPCOMING_`.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(10))
            .tracking(1.6)
            .foregroundStyle(Theme.label)
    }
}

/// Colored status dot + mono caption (sync status, etc).
struct SyncDot: View {
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.label)
        }
    }
}

/// Square (radius 0) checkbox outline.
struct SquareCheckbox: View {
    var size: CGFloat = 13
    var body: some View {
        Rectangle()
            .stroke(Color(hex: "2E2E2E"), lineWidth: 1)
            .frame(width: size, height: size)
    }
}

/// 5pt priority dot.
struct PriorityDot: View {
    let priority: LifeTaskPriority
    var body: some View {
        Circle()
            .fill(Theme.priorityColor(priority))
            .frame(width: 5, height: 5)
    }
}

/// 2px vertical accent bar used beside event rows.
struct AccentBar: View {
    var color: Color
    var height: CGFloat
    var body: some View {
        Rectangle().fill(color).frame(width: 2, height: height)
    }
}
