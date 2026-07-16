import Foundation
import UIKit

@MainActor
final class RemoteNotificationRegistration: ObservableObject {
    enum State: Equatable {
        case notRequested
        case registering
        case registered(tokenPrefix: String)
        case failed(String)
    }

    static let shared = RemoteNotificationRegistration()

    @Published private(set) var state: State = .notRequested
    @Published private(set) var apsEnvironment: String?

    private init() {
        refreshEntitlement()
    }

    var diagnosticLabel: String {
        let entitlement = apsEnvironment.map { "aps=\($0)" } ?? "aps missing"
        switch state {
        case .notRequested:
            return "Not requested · \(entitlement)"
        case .registering:
            return "Requesting token · \(entitlement)"
        case .registered(let tokenPrefix):
            return "Token \(tokenPrefix)… · \(entitlement)"
        case .failed(let message):
            return "Failed · \(message) · \(entitlement)"
        }
    }

    var health: DiagnosticHealth {
        switch state {
        case .registered:
            return apsEnvironment == nil ? .warning : .good
        case .failed:
            return .bad
        case .registering, .notRequested:
            return apsEnvironment == nil ? .bad : .warning
        }
    }

    func beginRegistration() {
        refreshEntitlement()
        state = .registering
        UIApplication.shared.registerForRemoteNotifications()
    }

    func didRegister(deviceToken: Data) {
        refreshEntitlement()
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        state = .registered(tokenPrefix: String(token.prefix(12)))
        NSLog(
            "[PRLife][push-gate] device token received; aps-environment=%@",
            apsEnvironment ?? "missing"
        )
    }

    func didFail(_ error: Error) {
        refreshEntitlement()
        state = .failed(error.localizedDescription)
        NSLog(
            "[PRLife][push-gate] registration failed; aps-environment=%@; error=%@",
            apsEnvironment ?? "missing",
            error.localizedDescription
        )
    }

    private func refreshEntitlement() {
        guard let profileURL = Bundle.main.url(
            forResource: "embedded",
            withExtension: "mobileprovision"
        ),
        let profileData = try? Data(contentsOf: profileURL),
        let plistData = Self.embeddedPropertyList(in: profileData),
        let profileObject = try? PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        ),
        let profile = profileObject as? [String: Any],
        let entitlements = profile["Entitlements"] as? [String: Any],
        let value = entitlements["aps-environment"] as? String else {
            apsEnvironment = nil
            return
        }
        apsEnvironment = value
    }

    /// Provisioning profiles are CMS envelopes containing an XML property list.
    /// Reading the embedded profile works in the iOS sandbox and audits the profile
    /// SideStore actually installed, rather than assuming the source entitlement survived.
    private static func embeddedPropertyList(in data: Data) -> Data? {
        guard let startMarker = "<?xml".data(using: .utf8),
              let endMarker = "</plist>".data(using: .utf8),
              let start = data.range(of: startMarker),
              let end = data.range(of: endMarker, options: .backwards),
              start.lowerBound < end.upperBound else { return nil }
        return data.subdata(in: start.lowerBound..<end.upperBound)
    }
}

final class PRLifeApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Task { @MainActor in
            RemoteNotificationRegistration.shared.beginRegistration()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            RemoteNotificationRegistration.shared.didRegister(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            RemoteNotificationRegistration.shared.didFail(error)
        }
    }
}
