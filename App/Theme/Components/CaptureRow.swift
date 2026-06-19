import SwiftUI
import PRLifeKit

struct CaptureRow: View {
    let record: CaptureRecord
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
                Text(record.context.displayName.uppercased()).font(Theme.mono(11)).foregroundStyle(Theme.label)
            }
            if let t = record.transcript, !t.isEmpty {
                Text(t).font(Theme.body(12)).foregroundStyle(Color(hex: "555555")).lineLimit(1)
            }
            if record.status == .processing || record.status == .uploading {
                Rectangle().fill(Theme.accent).frame(height: 2)
            }
        }
        .padding(.vertical, 15).padding(.horizontal, 20)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.hairline), alignment: .top)
    }
}
