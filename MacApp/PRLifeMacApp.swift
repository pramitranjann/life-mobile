import SwiftUI
import PRLifeKit

@main
struct PRLifeMacApp: App {
    @StateObject private var env = MacCaptureEnvironment.shared

    init() {
        FontRegistration.registerAll()
        MacCaptureEnvironment.shared.startHotKeys()
    }

    var body: some Scene {
        MenuBarExtra("PR Life", systemImage: env.isRecording ? "waveform.circle.fill" : "waveform") {
            Text(env.isRecording ? "Recording \(env.recordingContext?.displayName ?? "")…" : "PR Life_")
                .font(Theme.display(18))
                .foregroundStyle(env.isRecording ? Theme.accent : Theme.text)
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
