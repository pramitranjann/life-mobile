import SwiftUI
import PRLifeKit

@main
struct PRLifeMacApp: App {
    @StateObject private var env = MacCaptureEnvironment.shared
    @StateObject private var sync: LifeSyncService
    @StateObject private var notifications: LifeNotificationService

    init() {
        FontRegistration.registerAll()
        MacCaptureEnvironment.shared.startHotKeys()
        let notificationService = LifeNotificationService(
            api: MacCaptureEnvironment.shared.api,
            cursorStore: UserDefaultsLifeNotificationCursorStore(
                key: UserDefaultsLifeNotificationCursorStore.macOSKey
            ),
            scheduler: UserNotificationPresenter()
        )
        let service = LifeSyncService(
            api: MacCaptureEnvironment.shared.api,
            notificationService: notificationService
        )
        _notifications = StateObject(wrappedValue: notificationService)
        _sync = StateObject(wrappedValue: service)
        service.startPeriodicRefresh()   // spec §7: refresh on launch + every ~15 min
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
