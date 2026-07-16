import SwiftUI
import SwiftData
import PRLifeKit

@main
struct PRLifeMobileApp: App {
    private let env = CaptureEnvironment.shared
    private let notificationPresenter: UserNotificationPresenter
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var notifications: LifeNotificationService
    @StateObject private var eventReminders: LifeEventReminderService

    init() {
        let presenter = UserNotificationPresenter()
        notificationPresenter = presenter
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
            MainView(
                coordinator: env.coordinator,
                store: env.store,
                api: env.api,
                notificationPresenter: notificationPresenter
            )
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
        // Permission must be requested before any network request. A slow or unreachable API
        // should never prevent PR Life from registering with iOS notification settings.
        do {
            _ = try await notificationPresenter.requestAuthorization()
        } catch {
            NSLog("[PRLife][notifications] authorization failed: %@", "\(error)")
        }

        async let alertRefresh: Void = notifications.refresh()
        async let eventRefresh: Void = eventReminders.refresh()
        _ = await (alertRefresh, eventRefresh)
    }
}
