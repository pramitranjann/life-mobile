import SwiftUI

@main
struct PRLifeMacApp: App {
    init() { FontRegistration.registerAll() }

    var body: some Scene {
        MenuBarExtra("PR Life", systemImage: "waveform") {
            Text("PR Life_")
                .font(Theme.display(22))
                .foregroundStyle(Theme.text)
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
