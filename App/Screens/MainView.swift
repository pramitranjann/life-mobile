import SwiftUI
import PRLifeKit

struct MainView: View {
    let coordinator: CaptureCoordinator
    let store: SwiftDataCaptureStore
    @State private var records: [CaptureRecord] = []
    @State private var isRecording = false
    @State private var context: CaptureContext = .quick

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("LIFE_").font(Theme.mono(13, .medium)).tracking(1.3).foregroundStyle(Theme.text)
                Spacer()
                SyncDot()
                Text("SYNCED").font(Theme.mono(10)).foregroundStyle(Theme.label)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.hairline), alignment: .bottom)

            RecordButton(isRecording: isRecording,
                         onPress: { Task { await start() } },
                         onRelease: { Task { await stop() } })
                .padding(14)

            SectionLabel(text: "CAPTURES_", trailing: "\(records.count) total")
                .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 10)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(records) { CaptureRow(record: $0) }
                }
            }
            Spacer(minLength: 0)
        }
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { refresh() }
    }

    private func start() async { await coordinator.handle(.startCapture(context: context)); isRecording = true; refresh() }
    private func stop() async { isRecording = false; await coordinator.handle(.stopCapture); refresh() }
    private func refresh() { records = store.all() }
}
