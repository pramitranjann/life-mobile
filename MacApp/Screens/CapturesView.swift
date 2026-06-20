import SwiftUI
import PRLifeKit

/// Captures tab: local capture history from the SwiftData store.
struct CapturesView: View {
    @ObservedObject var env: MacCaptureEnvironment
    @State private var records: [CaptureRecord] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                            CaptureRow(record: record)
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
