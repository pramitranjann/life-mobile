import Combine
import Foundation

@MainActor
public protocol LifeNotificationFetching {
    func fetchNotifications(after: Date?, limit: Int) async throws -> [LifeNotification]
}

@MainActor
public protocol LifeNotificationScheduling: AnyObject {
    func requestAuthorization() async throws -> Bool
    func schedule(_ notification: LifeNotification, isTimeSensitive: Bool) async throws
}

@MainActor
public protocol LifeNotificationCursorStoring: AnyObject {
    var lastDeliveredAt: Date? { get }
    func save(lastDeliveredAt: Date)
}

@MainActor
public final class UserDefaultsLifeNotificationCursorStore: LifeNotificationCursorStoring {
    public static let iOSKey = "lifeNotifications.lastDeliveredAt.ios"
    public static let macOSKey = "lifeNotifications.lastDeliveredAt.mac"

    private let key: String
    private let defaults: UserDefaults

    public init(key: String, defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    public var lastDeliveredAt: Date? {
        defaults.object(forKey: key) as? Date
    }

    public func save(lastDeliveredAt: Date) {
        defaults.set(lastDeliveredAt, forKey: key)
    }
}

@MainActor
public final class LifeNotificationService: ObservableObject {
    @Published public private(set) var lastError: String?

    private let api: LifeNotificationFetching
    private let cursorStore: LifeNotificationCursorStoring
    private let scheduler: LifeNotificationScheduling
    private let settingsProvider: @MainActor () -> LifeNotificationSettings
    private var isRefreshing = false

    public init(
        api: LifeNotificationFetching,
        cursorStore: LifeNotificationCursorStoring,
        scheduler: LifeNotificationScheduling,
        settingsProvider: @escaping @MainActor () -> LifeNotificationSettings = { .default }
    ) {
        self.api = api
        self.cursorStore = cursorStore
        self.scheduler = scheduler
        self.settingsProvider = settingsProvider
    }

    /// Polls the global notification feed with an installation-local cursor. API and
    /// scheduling failures stay here so callers can keep their normal sync state intact.
    public func refresh(now: Date = Date()) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            try await deliver(now: now)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            NSLog("[PRLife][notifications] refresh failed: %@", "\(error)")
        }
    }

    /// Exposed separately from `refresh` so delivery and cursor semantics can be tested.
    @discardableResult
    public func deliver(now: Date = Date()) async throws -> Int {
        let cursor = cursorStore.lastDeliveredAt
        let fetched = try await api.fetchNotifications(after: cursor, limit: 50)
        let settings = settingsProvider()
        if !settings.applicationAlertsEnabled {
            if let newest = fetched.max(by: { $0.createdAt < $1.createdAt })?.createdAt {
                cursorStore.save(lastDeliveredAt: newest)
            }
            return 0
        }
        let authorized = try await scheduler.requestAuthorization()
        guard authorized else { return 0 }

        let ordered = fetched.sorted {
            if $0.createdAt == $1.createdAt { return $0.id < $1.id }
            return $0.createdAt < $1.createdAt
        }
        let cutoff = now.addingTimeInterval(-24 * 60 * 60)
        var seenIDs = Set<String>()
        var deliveredCount = 0

        for notification in ordered {
            guard seenIDs.insert(notification.id).inserted else { continue }
            guard notification.kind == "program_application" else { continue }
            guard cursor != nil || notification.createdAt >= cutoff else { continue }
            let imminent = notification.isGenuinelyImminent(relativeTo: now)
            guard !settings.isQuietHour(now) || (settings.timeSensitiveEnabled && imminent) else {
                continue
            }
            try await scheduler.schedule(
                notification,
                isTimeSensitive: settings.timeSensitiveEnabled && imminent
            )
            deliveredCount += 1
        }

        // Save only after the entire fetched page has been handled successfully. This
        // prevents a failed item from being skipped by the API's strict `after` filter.
        if let newest = ordered.last?.createdAt {
            cursorStore.save(lastDeliveredAt: newest)
        }
        return deliveredCount
    }
}

extension LifeAPIClient: LifeNotificationFetching {}
