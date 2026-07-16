import Foundation

public enum LifeAPIBaseURL {
    public static func normalizedURL(from rawValue: String?) -> URL? {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }

        if let url = validatedURL(from: trimmed) {
            return url
        }

        guard !trimmed.contains("://") else { return nil }

        let scheme = shouldUseHTTP(for: trimmed) ? "http" : "https"
        return validatedURL(from: "\(scheme)://\(trimmed)")
    }

    public static func allowsInsecureHTTP(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "http" else { return true }
        guard let host = url.host(percentEncoded: false)?.lowercased() else { return false }
        return isLocalHost(host)
    }

    private static func validatedURL(from value: String) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host(percentEncoded: false),
              !host.isEmpty else {
            return nil
        }
        return url
    }

    private static func shouldUseHTTP(for value: String) -> Bool {
        let hostCandidate = value.split(separator: "/", maxSplits: 1).first.map(String.init) ?? value
        let host = hostCandidate.split(separator: ":", maxSplits: 1).first.map(String.init) ?? hostCandidate
        let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        return isLocalHost(normalized)
    }

    private static func isLocalHost(_ host: String) -> Bool {
        if host == "localhost" || host == "::1" || host == "0.0.0.0" || host.hasSuffix(".local") {
            return true
        }

        if host.hasPrefix("127.") || host.hasPrefix("10.") || host.hasPrefix("192.168.") || host.hasPrefix("169.254.") {
            return true
        }

        if host.hasPrefix("172.") {
            let octets = host.split(separator: ".")
            if octets.count >= 2, let secondOctet = Int(octets[1]), (16...31).contains(secondOctet) {
                return true
            }
        }

        return false
    }
}
