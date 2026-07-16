import Foundation

public enum LifeSyncStatus: String, Codable, Sendable, CaseIterable {
    case idle
    case syncing
    case synced
    case offline
    case notConfigured
    case authenticationFailed
    case failed
}

/// Shared sync and API-contact state for the native companion surfaces.
///
/// The timestamps intentionally distinguish an attempted operation from a
/// confirmed successful API response. Callers must not manufacture a `synced`
/// state from cached data or reachability alone.
public struct LifeSyncState: Sendable, Equatable {
    public var status: LifeSyncStatus
    public var lastSuccessfulAPIContact: Date?
    public var lastAttemptedSync: Date?
    public var currentError: String?
    public var pendingCaptureCount: Int

    public init(
        status: LifeSyncStatus = .idle,
        lastSuccessfulAPIContact: Date? = nil,
        lastAttemptedSync: Date? = nil,
        currentError: String? = nil,
        pendingCaptureCount: Int = 0
    ) {
        self.status = status
        self.lastSuccessfulAPIContact = lastSuccessfulAPIContact
        self.lastAttemptedSync = lastAttemptedSync
        self.currentError = currentError
        self.pendingCaptureCount = max(0, pendingCaptureCount)
    }

    public func beginningSync(at date: Date = Date()) -> LifeSyncState {
        var copy = self
        copy.status = .syncing
        copy.lastAttemptedSync = date
        copy.currentError = nil
        return copy
    }

    public func applying(
        _ connectivity: LifeAPIConnectivity,
        attemptedAt date: Date = Date()
    ) -> LifeSyncState {
        var copy = self
        copy.lastAttemptedSync = date

        switch connectivity {
        case .authenticated:
            copy.status = .synced
            copy.lastSuccessfulAPIContact = date
            copy.currentError = nil
        case .notConfigured:
            copy.status = .notConfigured
            copy.currentError = LifeAPIError.notConfigured.errorDescription
        case .authenticationFailed:
            copy.status = .authenticationFailed
            copy.currentError = "PR Life rejected the saved authentication token."
        case .offline:
            copy.status = .offline
            copy.currentError = "PR Life could not be reached over the network."
        case .failed(let message):
            copy.status = .failed
            copy.currentError = message
        }

        return copy
    }

    public func updatingPendingCaptureCount(_ count: Int) -> LifeSyncState {
        var copy = self
        copy.pendingCaptureCount = max(0, count)
        return copy
    }
}
