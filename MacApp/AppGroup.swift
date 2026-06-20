import Foundation

enum AppGroup {
    static let id = "group.com.pramitranjan.prlife"

    /// Shared container directory; falls back to Application Support if unavailable.
    static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
}
