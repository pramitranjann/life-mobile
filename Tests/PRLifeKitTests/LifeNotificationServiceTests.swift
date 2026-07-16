import XCTest
@testable import PRLifeKit

@MainActor
final class LifeNotificationServiceTests: XCTestCase {
    func test_deliverySortsOldestFirstAndDeduplicatesServerUUID() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let newer = notification(id: "new", createdAt: now.addingTimeInterval(-60))
        let older = notification(id: "old", createdAt: now.addingTimeInterval(-120))
        let api = NotificationAPISpy(notifications: [newer, older, older])
        let scheduler = NotificationSchedulerSpy()
        let cursor = NotificationCursorSpy()
        let service = LifeNotificationService(api: api, cursorStore: cursor, scheduler: scheduler)

        let delivered = try await service.deliver(now: now)

        XCTAssertEqual(delivered, 2)
        XCTAssertEqual(scheduler.scheduledIDs, ["old", "new"])
        XCTAssertEqual(cursor.lastDeliveredAt, newer.createdAt)
        XCTAssertEqual(api.requestedAfter, [nil])
        XCTAssertEqual(api.requestedLimits, [50])
    }

    func test_cursorAdvancesOnlyAfterEveryScheduleSucceeds() async {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let existingCursor = now.addingTimeInterval(-300)
        let cursor = NotificationCursorSpy(lastDeliveredAt: existingCursor)
        let api = NotificationAPISpy(notifications: [
            notification(id: "one", createdAt: now.addingTimeInterval(-120)),
            notification(id: "two", createdAt: now.addingTimeInterval(-60))
        ])
        let scheduler = NotificationSchedulerSpy(failingID: "two")
        let service = LifeNotificationService(api: api, cursorStore: cursor, scheduler: scheduler)

        do {
            _ = try await service.deliver(now: now)
            XCTFail("expected scheduling error")
        } catch {
            XCTAssertEqual(error as? NotificationTestError, .scheduling)
        }

        XCTAssertEqual(scheduler.scheduledIDs, ["one"])
        XCTAssertEqual(cursor.lastDeliveredAt, existingCursor)
        XCTAssertEqual(cursor.saveCount, 0)
    }

    func test_firstSyncOnlyDeliversPrevious24HoursThenSavesNewestTimestamp() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let old = notification(id: "old", createdAt: now.addingTimeInterval(-25 * 60 * 60))
        let recent = notification(id: "recent", createdAt: now.addingTimeInterval(-60))
        let unrelated = notification(id: "other", kind: "system", createdAt: now)
        let scheduler = NotificationSchedulerSpy()
        let cursor = NotificationCursorSpy()
        let service = LifeNotificationService(
            api: NotificationAPISpy(notifications: [unrelated, recent, old]),
            cursorStore: cursor,
            scheduler: scheduler
        )

        _ = try await service.deliver(now: now)

        XCTAssertEqual(scheduler.scheduledIDs, ["recent"])
        XCTAssertEqual(cursor.lastDeliveredAt, unrelated.createdAt)
    }

    func test_deniedAuthorizationDoesNotScheduleOrAdvanceCursor() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let cursor = NotificationCursorSpy()
        let scheduler = NotificationSchedulerSpy(isAuthorized: false)
        let service = LifeNotificationService(
            api: NotificationAPISpy(notifications: [notification(id: "n1", createdAt: now)]),
            cursorStore: cursor,
            scheduler: scheduler
        )

        let delivered = try await service.deliver(now: now)

        XCTAssertEqual(delivered, 0)
        XCTAssertTrue(scheduler.scheduledIDs.isEmpty)
        XCTAssertNil(cursor.lastDeliveredAt)
    }

    func test_iOSAndMacCursorKeysAreIndependent() {
        let suiteName = "LifeNotificationServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let ios = UserDefaultsLifeNotificationCursorStore(
            key: UserDefaultsLifeNotificationCursorStore.iOSKey,
            defaults: defaults
        )
        let mac = UserDefaultsLifeNotificationCursorStore(
            key: UserDefaultsLifeNotificationCursorStore.macOSKey,
            defaults: defaults
        )
        let iosDate = Date(timeIntervalSince1970: 1_000)
        let macDate = Date(timeIntervalSince1970: 2_000)

        ios.save(lastDeliveredAt: iosDate)
        mac.save(lastDeliveredAt: macDate)

        XCTAssertEqual(ios.lastDeliveredAt, iosDate)
        XCTAssertEqual(mac.lastDeliveredAt, macDate)
    }

    func test_quietHoursSuppressOrdinaryAlertButAdvanceInstallationCursor() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let alert = notification(id: "quiet", createdAt: now)
        let cursor = NotificationCursorSpy()
        let scheduler = NotificationSchedulerSpy()
        let service = LifeNotificationService(
            api: NotificationAPISpy(notifications: [alert]),
            cursorStore: cursor,
            scheduler: scheduler,
            settingsProvider: {
                LifeNotificationSettings(
                    quietHoursEnabled: true,
                    quietHoursStartMinutes: 0,
                    quietHoursEndMinutes: 0
                )
            }
        )

        let delivered = try await service.deliver(now: now)

        XCTAssertEqual(delivered, 0)
        XCTAssertTrue(scheduler.scheduledIDs.isEmpty)
        XCTAssertEqual(cursor.lastDeliveredAt, alert.createdAt)
    }

    func test_onlyServerTimestampWithinOneHourCanBeTimeSensitive() async throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-16T01:00:00Z"))
        let imminent = notification(
            id: "imminent",
            createdAt: now,
            metadata: ["deadline": "2026-07-16T01:30:00Z"]
        )
        let merelyNew = notification(id: "new", createdAt: now)
        let scheduler = NotificationSchedulerSpy()
        let service = LifeNotificationService(
            api: NotificationAPISpy(notifications: [imminent, merelyNew]),
            cursorStore: NotificationCursorSpy(),
            scheduler: scheduler,
            settingsProvider: { LifeNotificationSettings(timeSensitiveEnabled: true) }
        )

        _ = try await service.deliver(now: now)

        XCTAssertEqual(scheduler.scheduledIDs, ["imminent", "new"])
        XCTAssertEqual(scheduler.timeSensitiveIDs, ["imminent"])
    }

    func test_disabledApplicationAlertsAdvanceLocalCursorWithoutRequestingPermission() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let scheduler = NotificationSchedulerSpy()
        let cursor = NotificationCursorSpy()
        let service = LifeNotificationService(
            api: NotificationAPISpy(notifications: [notification(id: "n", createdAt: now)]),
            cursorStore: cursor,
            scheduler: scheduler,
            settingsProvider: { LifeNotificationSettings(applicationAlertsEnabled: false) }
        )

        let delivered = try await service.deliver(now: now)
        XCTAssertEqual(delivered, 0)
        XCTAssertEqual(scheduler.authorizationRequestCount, 0)
        XCTAssertEqual(cursor.lastDeliveredAt, now)
    }

    private func notification(
        id: String,
        kind: String = "program_application",
        createdAt: Date,
        metadata: [String: String] = ["status": "open"]
    ) -> LifeNotification {
        LifeNotification(
            id: id,
            kind: kind,
            title: "Applications open",
            body: "Apply now",
            url: URL(string: "https://example.com/apply"),
            metadata: metadata,
            createdAt: createdAt,
            readAt: nil
        )
    }
}

@MainActor
private final class NotificationAPISpy: LifeNotificationFetching {
    let notifications: [LifeNotification]
    private(set) var requestedAfter: [Date?] = []
    private(set) var requestedLimits: [Int] = []

    init(notifications: [LifeNotification]) {
        self.notifications = notifications
    }

    func fetchNotifications(after: Date?, limit: Int) async throws -> [LifeNotification] {
        requestedAfter.append(after)
        requestedLimits.append(limit)
        return notifications
    }
}

private enum NotificationTestError: Error, Equatable {
    case scheduling
}

@MainActor
private final class NotificationSchedulerSpy: LifeNotificationScheduling {
    let isAuthorized: Bool
    let failingID: String?
    private(set) var scheduledIDs: [String] = []
    private(set) var timeSensitiveIDs: [String] = []
    private(set) var authorizationRequestCount = 0

    init(isAuthorized: Bool = true, failingID: String? = nil) {
        self.isAuthorized = isAuthorized
        self.failingID = failingID
    }

    func requestAuthorization() async throws -> Bool {
        authorizationRequestCount += 1
        return isAuthorized
    }

    func schedule(_ notification: LifeNotification, isTimeSensitive: Bool) async throws {
        if notification.id == failingID { throw NotificationTestError.scheduling }
        scheduledIDs.append(notification.id)
        if isTimeSensitive { timeSensitiveIDs.append(notification.id) }
    }
}

@MainActor
private final class NotificationCursorSpy: LifeNotificationCursorStoring {
    private(set) var lastDeliveredAt: Date?
    private(set) var saveCount = 0

    init(lastDeliveredAt: Date? = nil) {
        self.lastDeliveredAt = lastDeliveredAt
    }

    func save(lastDeliveredAt: Date) {
        self.lastDeliveredAt = lastDeliveredAt
        saveCount += 1
    }
}
