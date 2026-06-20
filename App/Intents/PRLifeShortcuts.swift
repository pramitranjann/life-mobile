import AppIntents

struct PRLifeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartCaptureIntent(), phrases: ["Start \(.applicationName) capture"],
                    shortTitle: "Start Capture", systemImageName: "mic.fill")
        AppShortcut(intent: StopCaptureIntent(), phrases: ["Stop \(.applicationName) capture"],
                    shortTitle: "Stop Capture", systemImageName: "stop.fill")
    }
}
