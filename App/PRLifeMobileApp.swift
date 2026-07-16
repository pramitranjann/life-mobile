import SwiftUI
import SwiftData
import PRLifeKit

@main
struct PRLifeMobileApp: App {
    private let env = CaptureEnvironment.shared
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var notifications: LifeNotificationService
    @StateObject private var eventReminders: LifeEventReminderService

    init() {
        let presenter = UserNotificationPresenter()
        _notifications = StateObject(wrappedValue: LifeNotificationService(
            api: CaptureEnvironment.shared.api,
            cursorStore: UserDefaultsLifeNotificationCursorStore(
                key: UserDefaultsLifeNotificationCursorStore.iOSKey
            ),
            scheduler: presenter
        ))
        _eventReminders = StateObject(wrappedValue: LifeEventReminderService(
            api: CaptureEnvironment.shared.api,
            scheduler: presenter
        ))
    }

    var body: some Scene {
        WindowGroup {
            MainView(coordinator: env.coordinator, store: env.store, api: env.api, activity: env.activity)
                .task { await refreshNotifications() }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await refreshNotifications() }
                }
                .onOpenURL { url in
                    Task { await env.handleDeepLink(url) }
                }
        }
        .modelContainer(env.container)
    }

    private func refreshNotifications() async {
        await notifications.refresh()
        await eventReminders.refresh()
    }
}
