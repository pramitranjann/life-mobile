import Foundation

public enum LifeWidgetLoadFailure: Equatable, Sendable {
    case configurationRequired
    case authenticationRequired
    case temporary
}

public enum LifeWidgetSnapshotPolicy {
    public static func classify(_ error: Error) -> LifeWidgetLoadFailure {
        switch LifeAPIConnectivity.classify(error: error) {
        case .notConfigured:
            return .configurationRequired
        case .authenticationFailed:
            return .authenticationRequired
        case .offline, .failed, .authenticated:
            return .temporary
        }
    }

    /// Cached content is intentionally reused only for transient failures. Setup
    /// and authentication errors must remain explicit instead of looking offline.
    public static func cachedSnapshot(
        after failure: LifeWidgetLoadFailure,
        from store: LifeSnapshotStoring
    ) -> LifeSnapshot? {
        guard failure == .temporary else { return nil }
        return store.load()
    }
}
