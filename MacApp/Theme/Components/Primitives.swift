import SwiftUI
import PRLifeKit

/// DM Mono uppercase label with a trailing underscore, e.g. `UPCOMING_`.
/// Web `.eyebrow`: 11px mono, 0.16em tracking.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(11))
            .tracking(1.7)
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

// Checkbox and priority dot come from PRLifeKit (TaskCheckbox, PriorityDot),
// matching the web `.life-check` circle and 7px `.pri-dot`.

/// 2px vertical accent bar used beside event rows.
struct AccentBar: View {
    var color: Color
    var height: CGFloat
    var body: some View {
        Rectangle().fill(color).frame(width: 2, height: height)
    }
}
