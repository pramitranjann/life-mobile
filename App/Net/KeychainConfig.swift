import Foundation
import Security

enum KeychainConfig {
    private static let service = "com.pramitranjan.prlife"
    private static let accessGroup = "8QBV8WL699.com.pramitranjan.prlife.shared"
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

    private static func get(_ key: String) -> String? {
        // Try with the access group first; then without it (free Apple ID sideloads).
        if let value = copy(key, includeAccessGroup: true) { return value }
        if let value = copy(key, includeAccessGroup: false) { return value }
        guard let fallback = bundledDefaults[key] else { return nil }
        _ = set(fallback, key)
        return fallback
    }

    static func save(baseURL: String, token: String) -> Bool {
        let didSaveBaseURL = set(baseURL, "baseURL")
        let didSaveToken = set(token, "token")
        return didSaveBaseURL && didSaveToken
    }

    static var baseURL: String? { Self.get("baseURL") }
    static var token: String? { Self.get("token") }
}
