import AVFoundation
import Combine
import Foundation
import PRLifeKit
import UserNotifications

struct SideStoreRelease: Equatable {
    let version: String
    let build: String
    let downloadURL: URL

    var displayVersion: String { "\(version) (\(build))" }
}

enum DiagnosticHealth: Equatable {
    case neutral
    case good
    case warning
    case bad
}

@MainActor
final class AppDiagnostics: ObservableObject {
    static let sourceURL = URL(
        string: "https://raw.githubusercontent.com/pramitranjann/life-mobile/main/sidestore/apps.json"
    )!

    @Published private(set) var isRefreshing = false
    @Published private(set) var latestRelease: SideStoreRelease?
    @Published private(set) var releaseLookupError: String?
    @Published private(set) var apiConnectivity: LifeAPIConnectivity?
    @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var scheduledReminderCount = 0
    @Published private(set) var activeAudioInput: String?
    @Published private(set) var widgetConfiguration = "Checking"
    @Published private(set) var widgetConfigurationHealth: DiagnosticHealth = .neutral

    let installedVersion: String
    let installedBuild: String
    let runtimeBundleIdentifier: String

    private let environment: CaptureEnvironment
    private let notificationCenter: UNUserNotificationCenter
    private let session: URLSession

    init(
        environment: CaptureEnvironment,
        notificationCenter: UNUserNotificationCenter = .current(),
        session: URLSession = .shared,
        bundle: Bundle = .main
    ) {
        self.environment = environment
        self.notificationCenter = notificationCenter
        self.session = session
        installedVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        installedBuild = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        runtimeBundleIdentifier = bundle.bundleIdentifier ?? "Unknown"
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        refreshWidgetConfiguration()
        refreshAudioInput()

        let settings = await notificationCenter.notificationSettings()
        notificationStatus = settings.authorizationStatus
        let requests = await notificationCenter.pendingNotificationRequests()
        scheduledReminderCount = requests.filter { $0.identifier.hasPrefix("prlife.event.") }.count

        apiConnectivity = await environment.refreshAPIConnectivity()
        await refreshLatestRelease()
    }

    private func refreshLatestRelease() async {
        do {
            var request = URLRequest(url: Self.sourceURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 15
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let catalog = try JSONDecoder().decode(SideStoreCatalog.self, from: data)
            guard let release = catalog.apps.first?.versions.first,
                  let downloadURL = URL(string: release.downloadURL) else {
                throw SideStoreCatalogError.missingRelease
            }
            latestRelease = SideStoreRelease(
                version: release.version,
                build: release.buildVersion,
                downloadURL: downloadURL
            )
            releaseLookupError = nil
        } catch {
            latestRelease = nil
            releaseLookupError = error.localizedDescription
        }
    }

    private func refreshWidgetConfiguration() {
        if let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.id
        ) {
            if let configuration = FileLifeAPIConfigurationStore(directory: directory).load(),
               !configuration.baseURL.isEmpty,
               !configuration.token.isEmpty {
                widgetConfiguration = "Shared config present · widget access unverified"
                widgetConfigurationHealth = .warning
            } else {
                widgetConfiguration = "App Group available · config missing"
                widgetConfigurationHealth = .warning
            }
            return
        }

        if Self.hasBundledWidgetConfiguration {
            widgetConfiguration = "Bundled config active · settings not shared"
            widgetConfigurationHealth = .warning
        } else {
            widgetConfiguration = "Widget API config unavailable"
            widgetConfigurationHealth = .bad
        }
    }

    private func refreshAudioInput() {
        let session = AVAudioSession.sharedInstance()
        activeAudioInput = session.currentRoute.inputs.first?.portName
            ?? session.preferredInput?.portName
    }

    private static var hasBundledWidgetConfiguration: Bool {
        guard let url = Bundle.main.url(forResource: "LocalAPIConfig", withExtension: "plist"),
              let values = NSDictionary(contentsOf: url) as? [String: Any],
              let baseURL = values["baseURL"] as? String,
              let token = values["token"] as? String else {
            return false
        }
        return !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct SideStoreCatalog: Decodable {
    struct App: Decodable {
        struct Release: Decodable {
            let version: String
            let buildVersion: String
            let downloadURL: String
        }

        let versions: [Release]
    }

    let apps: [App]
}

private enum SideStoreCatalogError: LocalizedError {
    case missingRelease

    var errorDescription: String? {
        "The SideStore source does not contain a published PR Life build."
    }
}
