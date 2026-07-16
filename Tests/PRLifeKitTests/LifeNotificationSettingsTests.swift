import XCTest
@testable import PRLifeKit

final class LifeNotificationSettingsTests: XCTestCase {
    func test_overnightQuietHoursUseLocalCalendarTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Kuala_Lumpur"))
        let settings = LifeNotificationSettings(
            quietHoursEnabled: true,
            quietHoursStartMinutes: 22 * 60,
            quietHoursEndMinutes: 7 * 60
        )

        let atNight = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 16, hour: 23
        )))
        let inDay = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 16, hour: 12
        )))

        XCTAssertTrue(settings.isQuietHour(atNight, calendar: calendar))
        XCTAssertFalse(settings.isQuietHour(inDay, calendar: calendar))
    }

    func test_userDefaultsStorePersistsAllSettings() {
        let suiteName = "LifeNotificationSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsLifeNotificationSettingsStore(defaults: defaults)
        let expected = LifeNotificationSettings(
            calendarRemindersEnabled: false,
            applicationAlertsEnabled: false,
            calendarLeadTime: .thirtyMinutes,
            allDayReminderMinutes: 7 * 60 + 45,
            quietHoursEnabled: true,
            quietHoursStartMinutes: 23 * 60,
            quietHoursEndMinutes: 6 * 60,
            timeSensitiveEnabled: true
        )

        store.save(expected)

        XCTAssertEqual(store.settings, expected)
    }

    func test_notificationWithoutDestinationTimestampIsNeverImminent() {
        let now = Date(timeIntervalSince1970: 1_000)
        let notification = LifeNotification(
            id: "n",
            kind: "program_application",
            title: "New",
            body: "Recently created is not automatically urgent",
            url: nil,
            metadata: [:],
            createdAt: now,
            readAt: nil
        )

        XCTAssertFalse(notification.isGenuinelyImminent(relativeTo: now))
    }
}
