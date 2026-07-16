import SwiftUI
import SwiftData
import PRLifeKit

@main
struct PRLifeMobileApp: App {
    @UIApplicationDelegateAdaptor(PRLifeApplicationDelegate.self) private var appDelegate
    private let env = CaptureEnvironment.shared
    private let notificationPresenter: UserNotificationPresenter
    private let notificationSettingsStore: UserDefaultsLifeNotificationSettingsStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var notifications: LifeNotificationService
    @StateObject private var eventReminders: LifeEventReminderService

    init() {
        let settingsStore = UserDefaultsLifeNotificationSettingsStore()
        notificationSettingsStore = settingsStore
        let presenter = UserNotificationPresenter(calendarDestinationURL: { reminder in
            guard let rawBaseURL = KeychainConfig.baseURL,
                  let baseURL = LifeAPIBaseURL.normalizedURL(from: rawBaseURL),
                  let routeURL = URL(string: LifeWebRoute.calendar(eventID: reminder.eventID).path,
                                     relativeTo: baseURL) else { return nil }
            return routeURL.absoluteURL
        })
        notificationPresenter = presenter
        _notifications = StateObject(wrappedValue: LifeNotificationService(
            api: CaptureEnvironment.shared.api,
            cursorStore: UserDefaultsLifeNotificationCursorStore(
                key: UserDefaultsLifeNotificationCursorStore.iOSKey
            ),
            scheduler: presenter,
            settingsProvider: { settingsStore.settings }
        ))
        _eventReminders = StateObject(wrappedValue: LifeEventReminderService(
            api: CaptureEnvironment.shared.api,
            scheduler: presenter,
            settingsProvider: { settingsStore.settings }
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
                .onReceive(NotificationCenter.default.publisher(for: .lifeNotificationSettingsDidChange)) { _ in
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
        NotificationCenter.default.post(name: .lifeNotificationRefreshDidFinish, object: nil)
    }
}
