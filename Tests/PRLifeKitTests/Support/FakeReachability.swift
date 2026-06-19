@testable import PRLifeKit

final class FakeReachability: ReachabilityProviding, @unchecked Sendable {
    var status: ConnectivityStatus
    init(_ status: ConnectivityStatus) { self.status = status }
    func current() -> ConnectivityStatus { status }
}
