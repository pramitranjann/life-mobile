import Foundation
import Network
import PRLifeKit

/// Network reachability for macOS via NWPathMonitor.
final class PathMonitorReachability: ReachabilityProviding, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "prlife.pathmonitor")
    private let lock = NSLock()
    private var status: ConnectivityStatus = .offline

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let next: ConnectivityStatus
            if path.status != .satisfied { next = .offline }
            else if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) { next = .wifi }
            else { next = .cellular }
            self.lock.lock(); self.status = next; self.lock.unlock()
        }
        monitor.start(queue: queue)
    }

    func current() -> ConnectivityStatus {
        lock.lock(); defer { lock.unlock() }
        return status
    }
}
