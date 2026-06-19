import Foundation

public enum ConnectivityStatus: Sendable, Equatable {
    case wifi, cellular, offline
}

public protocol ReachabilityProviding: Sendable {
    func current() -> ConnectivityStatus
}

public struct UploadGate {
    private let reachability: ReachabilityProviding
    private let wifiOnly: Bool

    public init(reachability: ReachabilityProviding, wifiOnly: Bool) {
        self.reachability = reachability
        self.wifiOnly = wifiOnly
    }

    public func canUploadNow() -> Bool {
        switch reachability.current() {
        case .offline: return false
        case .cellular: return !wifiOnly
        case .wifi: return true
        }
    }
}
