import SwiftUI
import SwiftData
import PRLifeKit

@main
struct PRLifeMobileApp: App {
    private let env = CaptureEnvironment.shared
    var body: some Scene {
        WindowGroup {
            MainView(coordinator: env.coordinator, store: env.store, api: env.api, activity: env.activity)
                .onOpenURL { url in
                    Task { await env.handleDeepLink(url) }
                }
        }
        .modelContainer(env.container)
    }
}
