import SwiftUI
import PRLifeKit

struct StatusBadge: View {
    let status: CaptureStatus
    private var color: Color {
        switch status {
        case .done: return Theme.green
        case .failed: return Theme.danger
        case .recording, .processing, .reviewing, .uploading: return Theme.accent
        }
    }
    var body: some View {
        Text(status.badgeLabel).font(Theme.mono(11, .medium)).foregroundStyle(color)
    }
}
