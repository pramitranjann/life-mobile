import SwiftUI
import UIKit
import UserNotifications
import PRLifeKit

@MainActor
struct DevicesView: View {
    @ObservedObject private var environment = CaptureEnvironment.shared
    @StateObject private var diagnostics = AppDiagnostics(environment: .shared)
    @ObservedObject private var pushRegistration = RemoteNotificationRegistration.shared

    private enum Field: Hashable {
        case baseURL
        case token
    }

    private enum SaveState {
        case idle
        case sharedWithWidget
        case appOnlyWithBundledWidget
        case appOnlyWithoutWidgetConfiguration
        case failure
    }

    let notificationPresenter: UserNotificationPresenter

    private let notificationSettingsStore = UserDefaultsLifeNotificationSettingsStore()
    @State private var baseURL = KeychainConfig.baseURL ?? ""
    @State private var token = KeychainConfig.token ?? ""
    @State private var saveState: SaveState = .idle
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var notificationError: String?
    @State private var notificationSettings = UserDefaultsLifeNotificationSettingsStore().settings
    @State private var scheduledReminderCount = 0
    @State private var testNotificationSent = false
    @AppStorage("wifiOnly") private var wifiOnly = false
    @AppStorage("backgroundRecording") private var backgroundRecording = true
    @AppStorage("reviewVoiceBeforeUpload") private var reviewVoiceBeforeUpload = false
    @FocusState private var focusedField: Field?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section("PR LIFE API_") {
                    field("Base URL", text: $baseURL, field: .baseURL)
                    field("Token", text: $token, secure: true, field: .token)
                    Button { saveAPIConfig() } label: {
                        Text("SAVE_")
                            .font(Theme.mono(13, .medium))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .overlay(Rectangle().stroke(Theme.accent, lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                    if saveState == .sharedWithWidget {
                        Text("Saved. App and widget will use this shared API config.")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.green)
                    } else if saveState == .appOnlyWithBundledWidget {
                        Text("Saved for the app. Widget continues using the release's bundled API config.")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.label)
                    } else if saveState == .appOnlyWithoutWidgetConfiguration {
                        Text("Saved for the app. Widget configuration is unavailable in this signed build.")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.danger)
                    } else if saveState == .failure {
                        Text("Save failed. The previous API configuration remains active.")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.danger)
                    }
                }
                section("RECORDING_") {
                    toggleRow("Background recording", "Screen off, app in background", $backgroundRecording)
                    toggleRow(
                        "Review voice before upload",
                        "Keep the transcript pending until you approve it",
                        $reviewVoiceBeforeUpload
                    )
                    toggleRow("Upload on WiFi only", "Save mobile data", $wifiOnly)
                }
                section("NOTIFICATIONS_") {
                    notificationRow
                    toggleRow(
                        "Calendar reminders",
                        "Schedule upcoming web calendar events",
                        settingsBinding(\.calendarRemindersEnabled)
                    )
                    toggleRow(
                        "Application alerts",
                        "Program openings and other server alerts",
                        settingsBinding(\.applicationAlertsEnabled)
                    )
                    notificationLeadTimeRow
                    notificationTimeRow(
                        "All-day reminder",
                        "Owner-local time",
                        minutes: settingsMinuteBinding(\.allDayReminderMinutes)
                    )
                    toggleRow(
                        "Quiet hours",
                        "Suppress non-urgent alerts in this window",
                        settingsBinding(\.quietHoursEnabled)
                    )
                    if notificationSettings.quietHoursEnabled {
                        notificationTimeRow(
                            "Quiet hours start",
                            "Local device time",
                            minutes: settingsMinuteBinding(\.quietHoursStartMinutes)
                        )
                        notificationTimeRow(
                            "Quiet hours end",
                            "Local device time",
                            minutes: settingsMinuteBinding(\.quietHoursEndMinutes)
                        )
                    }
                    toggleRow(
                        "Time Sensitive",
                        "Only alerts tied to something within one hour can bypass quiet delivery",
                        settingsBinding(\.timeSensitiveEnabled)
                    )
                    HStack(spacing: 10) {
                        diagnosticAction("SEND TEST_") { sendTestNotification() }
                        NavigationLink {
                            NotificationInboxView(api: environment.api)
                        } label: {
                            Text("ALERT INBOX_")
                                .font(Theme.mono(12, .medium))
                                .foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .overlay(Rectangle().stroke(Theme.accentLine, lineWidth: 1))
                        }
                    }
                    Text(
                        testNotificationSent
                            ? "Test sent · \(scheduledReminderCount) calendar reminders scheduled"
                            : "\(scheduledReminderCount) calendar reminders scheduled"
                    )
                    .font(Theme.mono(11))
                    .foregroundStyle(testNotificationSent ? Theme.green : Theme.label)
                    if let notificationError {
                        Text(notificationError)
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.danger)
                    }
                }
                section("DIAGNOSTICS_") {
                    diagnosticsRow(
                        "Installed build",
                        "\(diagnostics.installedVersion) (\(diagnostics.installedBuild))",
                        health: .good
                    )
                    diagnosticsRow(
                        "Runtime bundle ID",
                        diagnostics.runtimeBundleIdentifier,
                        health: .neutral
                    )
                    diagnosticsRow(
                        "Published build",
                        publishedBuildLabel,
                        health: publishedBuildHealth
                    )
                    diagnosticsRow("API", apiConnectivityLabel, health: apiConnectivityHealth)
                    diagnosticsRow(
                        "Widget",
                        diagnostics.widgetConfiguration,
                        health: diagnostics.widgetConfigurationHealth
                    )
                    diagnosticsRow(
                        "Notifications",
                        "\(diagnosticNotificationLabel) · \(diagnostics.scheduledReminderCount) scheduled",
                        health: diagnosticNotificationHealth
                    )
                    diagnosticsRow(
                        "APNs feasibility",
                        pushRegistration.diagnosticLabel,
                        health: pushRegistration.health
                    )
                    diagnosticsRow(
                        "Audio input",
                        diagnostics.activeAudioInput ?? "No active input",
                        health: diagnostics.activeAudioInput == nil ? .neutral : .good
                    )
                    diagnosticsRow(
                        "Last API contact",
                        lastAPIContactLabel,
                        health: environment.syncState.lastSuccessfulAPIContact == nil ? .neutral : .good
                    )
                    HStack(spacing: 10) {
                        diagnosticAction("CHECK FOR UPDATE_") {
                            Task { await diagnostics.refresh() }
                        }
                        diagnosticAction("INSTALL LATEST BUILD_") {
                            let url = diagnostics.latestRelease?.downloadURL ?? AppDiagnostics.sourceURL
                            UIApplication.shared.open(url)
                        }
                    }
                    diagnosticAction("RETRY APNS GATE_") {
                        pushRegistration.beginRegistration()
                    }
                    if let error = diagnostics.releaseLookupError {
                        Text("Source check failed: \(error)")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.danger)
                    }
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
        .task {
            await refreshNotificationStatus()
            scheduledReminderCount = await notificationPresenter.scheduledEventReminderCount()
            await diagnostics.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lifeNotificationRefreshDidFinish)) { _ in
            Task {
                scheduledReminderCount = await notificationPresenter.scheduledEventReminderCount()
                await diagnostics.refresh()
            }
        }
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
                Text(subtitle).font(Theme.mono(11)).foregroundStyle(Theme.label)
            }
            Spacer(); SquareToggle(isOn: isOn)
        }
        .padding(.horizontal, 13).padding(.vertical, 4)
        .background(Theme.panel).overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { isOn.wrappedValue.toggle() }   // whole row toggles
    }
    private var notificationRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("System permission")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.text)
                Text(notificationStatusLabel)
                    .font(Theme.mono(11))
                    .foregroundStyle(notificationStatusColor)
            }
            Spacer(minLength: 8)
            if !notificationIsEnabled {
                Button(notificationStatus == .denied ? "OPEN SETTINGS_" : "ENABLE_") {
                    notificationAction()
                }
                .font(Theme.mono(12, .medium))
                .foregroundStyle(Theme.accent)
                .frame(minWidth: 104, minHeight: 44)
                .contentShape(Rectangle())
                .overlay(Rectangle().stroke(Theme.accentLine, lineWidth: 1))
            }
        }
        .padding(.leading, 13)
        .padding(.trailing, notificationIsEnabled ? 13 : 0)
        .frame(minHeight: 54)
        .background(Theme.panel)
        .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
    }

    private var notificationLeadTimeRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Calendar lead time").font(Theme.body(13)).foregroundStyle(Theme.text)
                Text("Existing requests are replaced when this changes")
                    .font(Theme.mono(11)).foregroundStyle(Theme.label)
            }
            Spacer(minLength: 8)
            Picker("Lead time", selection: Binding(
                get: { notificationSettings.calendarLeadTime },
                set: {
                    notificationSettings.calendarLeadTime = $0
                    saveNotificationSettings()
                }
            )) {
                ForEach(LifeNotificationLeadTime.allCases) { leadTime in
                    Text(leadTime.displayName).tag(leadTime)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(Theme.accent)
        }
        .padding(13).background(Theme.panel)
        .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
    }

    private func notificationTimeRow(_ title: String, _ subtitle: String, minutes: Binding<Int>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.body(13)).foregroundStyle(Theme.text)
                Text(subtitle).font(Theme.mono(11)).foregroundStyle(Theme.label)
            }
            Spacer(minLength: 8)
            DatePicker("", selection: timeBinding(minutes), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .tint(Theme.accent)
        }
        .padding(13).background(Theme.panel)
        .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
    }
    private func mutedRow(_ title: String, _ badge: String) -> some View {
        HStack {
            Text(title).font(Theme.body(13)).foregroundStyle(Theme.label)
            Spacer()
            Text(badge).font(Theme.mono(10)).foregroundStyle(Theme.muted)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
        }
        .padding(14).background(Theme.mutedBG).overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
    }

    private func diagnosticsRow(_ title: String, _ value: String, health: DiagnosticHealth) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.label)
            Spacer(minLength: 10)
            Text(value)
                .font(Theme.mono(11, .medium))
                .foregroundStyle(color(for: health))
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 44)
        .background(Theme.panel)
        .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
    }

    private func diagnosticAction(
        _ title: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.mono(12, .medium))
                .foregroundStyle(enabled ? Theme.accent : Theme.label)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(
                    Rectangle().stroke(enabled ? Theme.accentLine : Theme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
    }

    private func saveAPIConfig() {
        focusedField = nil
        let outcome = KeychainConfig.save(
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            token: token.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        switch outcome {
        case .sharedWithWidget:
            saveState = .sharedWithWidget
        case .appOnlyWithBundledWidget:
            saveState = .appOnlyWithBundledWidget
        case .appOnlyWithoutWidgetConfiguration:
            saveState = .appOnlyWithoutWidgetConfiguration
        case .failed:
            saveState = .failure
        }
        Task { await diagnostics.refresh() }
    }

    private var notificationIsEnabled: Bool {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            true
        case .notDetermined, .denied:
            false
        @unknown default:
            false
        }
    }

    private var notificationStatusLabel: String {
        switch notificationStatus {
        case .notDetermined: "Permission not requested"
        case .denied: "Blocked in iOS Settings"
        case .authorized: "Enabled · \(notificationSettings.calendarLeadTime.displayName) before events"
        case .provisional: "Delivered quietly · \(notificationSettings.calendarLeadTime.displayName) before"
        case .ephemeral: "Temporarily enabled"
        @unknown default: "Status unavailable"
        }
    }

    private var notificationStatusColor: Color {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: Theme.green
        case .denied: Theme.danger
        case .notDetermined: Theme.label
        @unknown default: Theme.label
        }
    }

    private func notificationAction() {
        if notificationStatus == .denied {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
            return
        }

        Task {
            do {
                _ = try await notificationPresenter.requestAuthorization()
                notificationError = nil
            } catch {
                notificationError = "Permission request failed: \(error.localizedDescription)"
            }
            await refreshNotificationStatus()
            await diagnostics.refresh()
        }
    }

    private func settingsBinding(_ keyPath: WritableKeyPath<LifeNotificationSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { notificationSettings[keyPath: keyPath] },
            set: {
                notificationSettings[keyPath: keyPath] = $0
                saveNotificationSettings()
            }
        )
    }

    private func settingsMinuteBinding(
        _ keyPath: WritableKeyPath<LifeNotificationSettings, Int>
    ) -> Binding<Int> {
        Binding(
            get: { notificationSettings[keyPath: keyPath] },
            set: {
                notificationSettings[keyPath: keyPath] = min(max($0, 0), 24 * 60 - 1)
                saveNotificationSettings()
            }
        )
    }

    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                let calendar = Calendar.current
                let start = calendar.startOfDay(for: Date())
                return calendar.date(byAdding: .minute, value: minutes.wrappedValue, to: start) ?? start
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }

    private func saveNotificationSettings() {
        notificationSettingsStore.save(notificationSettings)
        testNotificationSent = false
        NotificationCenter.default.post(name: .lifeNotificationSettingsDidChange, object: nil)
    }

    private func sendTestNotification() {
        Task {
            do {
                try await notificationPresenter.sendTestNotification()
                notificationError = nil
                testNotificationSent = true
            } catch {
                notificationError = "Test failed: \(error.localizedDescription)"
                testNotificationSent = false
            }
            await refreshNotificationStatus()
        }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await notificationPresenter.authorizationStatus()
    }

    private var publishedBuildLabel: String {
        if let release = diagnostics.latestRelease {
            return release.displayVersion
        }
        return diagnostics.isRefreshing ? "Checking" : "Unavailable"
    }

    private var publishedBuildHealth: DiagnosticHealth {
        guard let release = diagnostics.latestRelease else { return .neutral }
        if release.version == diagnostics.installedVersion,
           release.build == diagnostics.installedBuild {
            return .good
        }
        if let published = Int(release.build),
           let installed = Int(diagnostics.installedBuild),
           published > installed {
            return .warning
        }
        return .neutral
    }

    private var apiConnectivityLabel: String {
        switch diagnostics.apiConnectivity {
        case nil: diagnostics.isRefreshing ? "Checking" : "Not checked"
        case .authenticated: "Configured · authenticated"
        case .notConfigured: "Not configured"
        case .authenticationFailed: "Authentication failed"
        case .offline: "Offline"
        case .failed(let message): "Failed · \(message)"
        }
    }

    private var apiConnectivityHealth: DiagnosticHealth {
        switch diagnostics.apiConnectivity {
        case .authenticated: .good
        case .notConfigured, .offline, nil: .warning
        case .authenticationFailed, .failed: .bad
        }
    }

    private var diagnosticNotificationLabel: String {
        switch diagnostics.notificationStatus {
        case .notDetermined: "Not requested"
        case .denied: "Denied"
        case .authorized: "Authorized"
        case .provisional: "Provisional"
        case .ephemeral: "Ephemeral"
        @unknown default: "Unavailable"
        }
    }

    private var diagnosticNotificationHealth: DiagnosticHealth {
        switch diagnostics.notificationStatus {
        case .authorized, .provisional, .ephemeral: .good
        case .notDetermined: .warning
        case .denied: .bad
        @unknown default: .neutral
        }
    }

    private var lastAPIContactLabel: String {
        guard let date = environment.syncState.lastSuccessfulAPIContact else {
            return "None"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func color(for health: DiagnosticHealth) -> Color {
        switch health {
        case .neutral: Theme.label
        case .good: Theme.green
        case .warning: Theme.amber
        case .bad: Theme.danger
        }
    }
}
