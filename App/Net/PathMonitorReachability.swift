import Foundation
import Network
import PRLifeKit

final class PathMonitorReachability: ReachabilityProviding, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var status: ConnectivityStatus = .offline

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let s: ConnectivityStatus
            if path.status != .satisfied { s = .offline }
            else if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) { s = .wifi }
            else { s = .cellular }
            self?.lock.lock(); self?.status = s; self?.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "reachability"))
    }
    func current() -> ConnectivityStatus { lock.lock(); defer { lock.unlock() }; return status }
}
