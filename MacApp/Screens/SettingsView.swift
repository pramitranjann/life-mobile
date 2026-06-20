import SwiftUI
import PRLifeKit

/// PR Life connection settings: base URL + mobile token (Keychain) and upload prefs.
struct SettingsView: View {
    @ObservedObject var sync: LifeSyncService

    @State private var baseURL: String = KeychainConfig.baseURL ?? ""
    @State private var token: String = KeychainConfig.token ?? ""
    @State private var wifiOnly: Bool = UserDefaults.standard.bool(forKey: "wifiOnly")
    @State private var saved = false

    var body: some View {
        Form {
            Section("PR Life API_") {
                TextField("Base URL", text: $baseURL, prompt: Text("https://your-pr-life.app"))
                    .textFieldStyle(.roundedBorder)
                SecureField("Mobile token", text: $token)
                    .textFieldStyle(.roundedBorder)
            }
            Section("Upload_") {
                Toggle("Upload on Wi-Fi only", isOn: $wifiOnly)
            }
            Section {
                HStack {
                    Button("Save") { save() }
                    if saved {
                        Text("Saved").font(Theme.mono(11)).foregroundStyle(Theme.green)
                    }
                    Spacer()
                    Button("Sync now") { Task { await sync.refresh() } }
                }
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func save() {
        _ = KeychainConfig.save(baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                                token: token.trimmingCharacters(in: .whitespacesAndNewlines))
        UserDefaults.standard.set(wifiOnly, forKey: "wifiOnly")
        saved = true
        Task { await sync.refresh() }
    }
}
