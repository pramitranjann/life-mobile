import SwiftUI
import SwiftData
import PRLifeKit

@main
struct PRLifeMobileApp: App {
    private let env = CaptureEnvironment.shared
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var notifications: LifeNotificationService

    init() {
        _notifications = StateObject(wrappedValue: LifeNotificationService(
            api: CaptureEnvironment.shared.api,
            cursorStore: UserDefaultsLifeNotificationCursorStore(
                key: UserDefaultsLifeNotificationCursorStore.iOSKey
            ),
            scheduler: UserNotificationPresenter()
        ))
    }

    var body: some Scene {
        WindowGroup {
            MainView(coordinator: env.coordinator, store: env.store, api: env.api, activity: env.activity)
                .task { await notifications.refresh() }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await notifications.refresh() }
                }
                .onOpenURL { url in
                    Task { await env.handleDeepLink(url) }
                }
        }
        .modelContainer(env.container)
    }
}
