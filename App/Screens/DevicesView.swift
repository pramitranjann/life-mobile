import SwiftUI

struct DevicesView: View {
    private enum Field: Hashable {
        case baseURL
        case token
    }

    private enum SaveState {
        case idle
        case success
        case failure
    }

    @State private var baseURL = KeychainConfig.baseURL ?? ""
    @State private var token = KeychainConfig.token ?? ""
    @State private var saveState: SaveState = .idle
    @AppStorage("wifiOnly") private var wifiOnly = false
    @AppStorage("backgroundRecording") private var backgroundRecording = true
    @FocusState private var focusedField: Field?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section("PR LIFE API_") {
                    field("Base URL", text: $baseURL, field: .baseURL)
                    field("Token", text: $token, secure: true, field: .token)
                    Button("Save") { saveAPIConfig() }
                        .font(Theme.mono(11, .medium)).foregroundStyle(Theme.accent)
                    if saveState == .success {
                        Text("Saved. Widgets will refresh with this API config.")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.green)
                    } else if saveState == .failure {
                        Text("Save failed. The widget could not access the shared config.")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.danger)
                    }
                }
                section("RECORDING_") {
                    toggleRow("Background recording", "Screen off, app in background", $backgroundRecording)
                    toggleRow("Upload on WiFi only", "Save mobile data", $wifiOnly)
                }
                section("DEVICES_") {
                    mutedRow("PR Life Pebble", "Not paired")
                    mutedRow("Apple Watch", "Coming soon")
                }
            }
            .padding(20)
        }
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private func section(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) { SectionLabel(text: label); content() }
    }
    private func field(_ title: String, text: Binding<String>, secure: Bool = false, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.mono(10)).foregroundStyle(Theme.label)
            Group {
                if secure {
                    SecureField("", text: text)
                } else {
                    TextField("https://your-pr-life.app or http://localhost:3000", text: text)
                }
            }
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(secure ? .asciiCapable : .URL)
                .textContentType(secure ? .password : .URL)
                .submitLabel(secure ? .done : .next)
                .focused($focusedField, equals: field)
                .onSubmit {
                    switch field {
                    case .baseURL:
                        focusedField = .token
                    case .token:
                        saveAPIConfig()
                    }
                }
                .font(Theme.body(13)).foregroundStyle(Theme.text)
                .padding(10).background(Theme.mutedBG)
                .overlay(Rectangle().stroke(Theme.border, lineWidth: 1))
        }
    }
    private func toggleRow(_ title: String, _ subtitle: String, _ isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.body(13)).foregroundStyle(Theme.text)
                Text(subtitle).font(Theme.mono(10)).foregroundStyle(Theme.label)
            }
            Spacer(); SquareToggle(isOn: isOn)
        }
        .padding(13).background(Theme.panel).overlay(Rectangle().stroke(Color(hex: "1E1E1E"), lineWidth: 1))
    }
    private func mutedRow(_ title: String, _ badge: String) -> some View {
        HStack {
            Text(title).font(Theme.body(13)).foregroundStyle(Color(hex: "3A3A3A"))
            Spacer()
            Text(badge).font(Theme.mono(9)).foregroundStyle(Color(hex: "2A2A2A"))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .overlay(Rectangle().stroke(Color(hex: "1A1A1A"), lineWidth: 1))
        }
        .padding(14).background(Theme.mutedBG).overlay(Rectangle().stroke(Color(hex: "1A1A1A"), lineWidth: 1))
    }

    private func saveAPIConfig() {
        focusedField = nil
        let didSave = KeychainConfig.save(
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            token: token.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        saveState = didSave ? .success : .failure
    }
}
