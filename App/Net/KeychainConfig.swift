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

    @discardableResult
    private static func set(_ value: String, _ key: String) -> Bool {
        let data = Data(value.utf8)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: key,
                                kSecAttrAccessGroup as String: accessGroup]
        SecItemDelete(q as CFDictionary)
        var add = q; add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
    private static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: key,
                                kSecAttrAccessGroup as String: accessGroup,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
           let d = item as? Data {
            return String(data: d, encoding: .utf8)
        }
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
