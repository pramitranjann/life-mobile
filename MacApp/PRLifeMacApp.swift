import SwiftUI
import PRLifeKit

@main
struct PRLifeMacApp: App {
    @StateObject private var env = MacCaptureEnvironment.shared
    @StateObject private var sync = LifeSyncService(api: MacCaptureEnvironment.shared.api)

    init() {
        FontRegistration.registerAll()
        MacCaptureEnvironment.shared.startHotKeys()
    }

    var body: some Scene {
        MenuBarExtra("PR Life", systemImage: env.isRecording ? "waveform.circle.fill" : "waveform") {
            MenuBarPopover(env: env, sync: sync)
        }
        .menuBarExtraStyle(.window)

        Window("PR Life", id: "dashboard") {
            MainWindow(env: env, sync: sync)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Settings {
            SettingsView(sync: sync)
        }
    }
}
