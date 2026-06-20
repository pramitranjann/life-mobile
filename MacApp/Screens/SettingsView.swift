import SwiftUI
import PRLifeKit

/// PR Life connection settings: base URL + mobile token (Keychain) and upload prefs.
struct SettingsView: View {
    @ObservedObject var sync: LifeSyncService

    @State private var baseURL: String = KeychainConfig.baseURL ?? ""
    @State private var token: String = KeychainConfig.token ?? ""
    @State private var wifiOnly: Bool = UserDefaults.standard.bool(forKey: "wifiOnly")
    @State private var saveResult: String?
    @State private var launchAtLogin: Bool = LoginItem.isEnabled
    @State private var loginError: String?

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
            Section("Startup_") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do { try LoginItem.setEnabled(enabled); loginError = nil }
                        catch {
                            loginError = "\(error.localizedDescription)"
                            launchAtLogin = LoginItem.isEnabled   // revert to actual state
                        }
                    }
                if let loginError {
                    Text(loginError).font(Theme.mono(11)).foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                HStack {
                    Button("Save") { save() }
                    if let saveResult {
                        Text(saveResult).font(Theme.mono(11))
                            .foregroundStyle(saveResult == "Saved" ? Theme.green : Theme.danger)
                    }
                    Spacer()
                    Button("Sync now") { Task { await sync.refresh() } }
                }
            }
            if case .failed(let message) = sync.state {
                Section("Last sync error_") {
                    Text(message).font(Theme.mono(11)).foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func save() {
        let ok = KeychainConfig.save(baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                                     token: token.trimmingCharacters(in: .whitespacesAndNewlines))
        UserDefaults.standard.set(wifiOnly, forKey: "wifiOnly")
        saveResult = ok ? "Saved" : "Keychain write failed"
        Task { await sync.refresh() }
    }
}
