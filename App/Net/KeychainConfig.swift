import Foundation
import PRLifeKit
import Security
import WidgetKit

enum KeychainConfigSaveOutcome: Equatable {
    case sharedWithWidget
    case appOnlyWithBundledWidget
    case appOnlyWithoutWidgetConfiguration
    case failed
}

enum KeychainConfig {
    private static let service = "com.pramitranjan.prlife"
    private static let accessGroup = "8QBV8WL699.com.pramitranjan.prlife.shared"
    private static let sharedContainerID = "group.com.pramitranjan.prlife"
    private static let bundledDefaults: [String: String] = {
        guard let url = Bundle.main.url(forResource: "LocalAPIConfig", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any] else {
            return [:]
        }
        return dict.reduce(into: [:]) { partialResult, entry in
            guard let value = entry.value as? String else { return }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            partialResult[entry.key] = trimmed
        }
    }()
    private static let bundledConfiguration = LifeAPIConfiguration(
        baseURL: bundledDefaults["baseURL"] ?? "",
        token: bundledDefaults["token"] ?? ""
    )

    /// Base query for a key. On free Apple IDs the hardcoded access group won't match the
    /// app's entitlements, so SecItem calls fail; callers retry without the access group.
    private static func baseQuery(_ key: String, includeAccessGroup: Bool) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: key]
        if includeAccessGroup {
            q[kSecAttrAccessGroup as String] = accessGroup
        }
        return q
    }

    private static func add(_ data: Data, _ key: String, includeAccessGroup: Bool) -> Bool {
        var add = baseQuery(key, includeAccessGroup: includeAccessGroup)
        add[kSecValueData as String] = data
        SecItemDelete(baseQuery(key, includeAccessGroup: includeAccessGroup) as CFDictionary)
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    private static func set(_ value: String, _ key: String) -> Bool {
        let data = Data(value.utf8)
        // Try with the access group first (paid accounts); fall back without it (free Apple IDs).
        if add(data, key, includeAccessGroup: true) { return true }
        return add(data, key, includeAccessGroup: false)
    }

    private static func copy(_ key: String, includeAccessGroup: Bool) -> String? {
        var q = baseQuery(key, includeAccessGroup: includeAccessGroup)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
           let d = item as? Data {
            return String(data: d, encoding: .utf8)
        }
        return nil
    }

    // Widget extensions should only trust the shared access group. Their no-access-group
    // keychain is a separate silo, so reading it would not reflect what the app saved.
    private static let isWidget: Bool = {
        let id = Bundle.main.bundleIdentifier ?? ""
        return id.contains("widgets") || id.contains("widget")
    }()

    private static func sharedStore() -> FileLifeAPIConfigurationStore? {
        guard let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: sharedContainerID
        ) else {
            return nil
        }
        return FileLifeAPIConfigurationStore(directory: directory)
    }

    private static func sharedValue(_ key: String) -> String? {
        guard let config = sharedStore()?.load() else { return nil }
        switch key {
        case "baseURL":
            return config.baseURL.isEmpty ? nil : config.baseURL
        case "token":
            return config.token.isEmpty ? nil : config.token
        default:
            return nil
        }
    }

    private static func get(_ key: String) -> String? {
        if let value = sharedValue(key) { return value }
        // Try the real shared access group first for both the app and widgets.
        if let value = copy(key, includeAccessGroup: true) { return value }
        // The main app can fall back to its local keychain on free Apple ID sideloads.
        if isWidget {
            switch key {
            case "baseURL":
                return bundledConfiguration.baseURL.isEmpty ? nil : bundledConfiguration.baseURL
            case "token":
                return bundledConfiguration.token.isEmpty ? nil : bundledConfiguration.token
            default:
                return nil
            }
        }
        if let value = copy(key, includeAccessGroup: false) { return value }
        switch key {
        case "baseURL":
            return bundledConfiguration.baseURL.isEmpty ? nil : bundledConfiguration.baseURL
        case "token":
            return bundledConfiguration.token.isEmpty ? nil : bundledConfiguration.token
        default:
            return nil
        }
    }

    static func save(baseURL: String, token: String) -> KeychainConfigSaveOutcome {
        let configuration = LifeAPIConfiguration(
            baseURL: LifeAPIBaseURL.normalizedURL(from: baseURL)?.absoluteString ?? baseURL,
            token: token
        )

        let didSaveShared: Bool
        if let store = sharedStore() {
            do {
                try store.save(configuration)
                didSaveShared = true
            } catch {
                didSaveShared = false
            }
        } else {
            didSaveShared = false
        }

        let didSaveBaseURL = set(configuration.baseURL, "baseURL")
        let didSaveToken = set(configuration.token, "token")

        if didSaveShared {
            WidgetCenter.shared.reloadAllTimelines()
            return .sharedWithWidget
        }

        guard didSaveBaseURL, didSaveToken else { return .failed }
        if !bundledConfiguration.baseURL.isEmpty, !bundledConfiguration.token.isEmpty {
            return .appOnlyWithBundledWidget
        }
        return .appOnlyWithoutWidgetConfiguration
    }

    static var baseURL: String? { Self.get("baseURL") }
    static var token: String? { Self.get("token") }
}
