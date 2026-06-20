import SwiftUI
import SwiftData
import PRLifeKit

@main
struct PRLifeMobileApp: App {
    private let env = CaptureEnvironment.shared
    var body: some Scene {
        WindowGroup {
            MainView(coordinator: env.coordinator, store: env.store, activity: env.activity)
        }
        .modelContainer(env.container)
    }
}
