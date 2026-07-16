import XCTest
@testable import PRLifeKit

@MainActor
final class LifeEventReminderServiceTests: XCTestCase {
    func test_synchronizesSevenOwnerLocalDaysAndSchedulesUpcomingEvents() async throws {
        let now = try XCTUnwrap(LifeEvent.parseISO("2026-07-16T01:00:00Z"))
        let timed = event(
            id: "timed",
            title: "Design review",
            start: "2026-07-16T02:00:00Z",
            localDate: "2026-07-16",
            location: "Studio"
        )
        let past = event(
            id: "past",
            title: "Already happened",
            start: "2026-07-16T00:00:00Z",
            localDate: "2026-07-16"
        )
        let allDay = event(
            id: "all-day",
            title: "Launch day",
            start: "2026-07-16T16:00:00Z",
            localDate: "2026-07-17",
            allDay: true
        )
        let today = LifeCalendarDay(
            localDate: "2026-07-16",
            timeZoneIdentifier: "Asia/Kuala_Lumpur",
            events: [timed, timed, past]
        )
        let api = EventReminderAPISpy(
            today: today,
            days: [
                "2026-07-17": LifeCalendarDay(
                    localDate: "2026-07-17",
                    timeZoneIdentifier: "Asia/Kuala_Lumpur",
                    events: [allDay]
                )
            ]
        )
        let scheduler = EventReminderSchedulerSpy()
        let service = LifeEventReminderService(
            api: api,
            scheduler: scheduler,
            lookAheadDays: 3,
            leadTime: 10 * 60
        )

        let count = try await service.synchronize(now: now)

        XCTAssertEqual(count, 2)
        XCTAssertEqual(api.requestedDates, [nil, "2026-07-17", "2026-07-18"])
        XCTAssertEqual(scheduler.replacements.count, 1)
        XCTAssertEqual(scheduler.replacements[0].map(\.eventID), ["timed", "all-day"])
        XCTAssertEqual(scheduler.replacements[0][0].body, "Starts in 10 minutes · Studio")
        XCTAssertEqual(
            scheduler.replacements[0][0].fireDate,
            try XCTUnwrap(LifeEvent.parseISO("2026-07-16T01:50:00Z"))
        )
        XCTAssertEqual(
            scheduler.replacements[0][1].fireDate,
            try XCTUnwrap(LifeEvent.parseISO("2026-07-17T01:00:00Z"))
        )
    }

    func test_eventInsideLeadWindowSchedulesImmediately() throws {
        let now = try XCTUnwrap(LifeEvent.parseISO("2026-07-16T01:55:00Z"))
        let event = event(
            id: "soon",
            title: "Standup",
            start: "2026-07-16T02:00:00Z",
            localDate: "2026-07-16"
        )

        let reminders = LifeEventReminderService.makeReminders(
            from: [event],
            timeZoneIdentifier: "Asia/Kuala_Lumpur",
            now: now,
            leadTime: 10 * 60,
            limit: 50
        )

        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders[0].fireDate, now.addingTimeInterval(2))
    }

    func test_deniedAuthorizationDoesNotFetchOrReplaceEvents() async throws {
        let api = EventReminderAPISpy(today: LifeCalendarDay(
            localDate: "2026-07-16",
            timeZoneIdentifier: "Asia/Kuala_Lumpur",
            events: []
        ))
        let scheduler = EventReminderSchedulerSpy(isAuthorized: false)
        let service = LifeEventReminderService(api: api, scheduler: scheduler)

        let count = try await service.synchronize()

        XCTAssertEqual(count, 0)
        XCTAssertTrue(api.requestedDates.isEmpty)
        XCTAssertTrue(scheduler.replacements.isEmpty)
    }

    func test_ownerLocalDateAdditionHandlesMonthBoundary() {
        XCTAssertEqual(
            LifeEventReminderService.addingDays(2, to: "2026-07-31"),
            "2026-08-02"
        )
    }

    private func event(
        id: String,
        title: String,
        start: String,
        localDate: String,
        location: String? = nil,
        allDay: Bool = false
    ) -> LifeEvent {
        LifeEvent(
            id: id,
            title: title,
            startTime: start,
            endTime: nil,
            allDay: allDay,
            location: location,
            localDate: localDate
        )
    }
}

@MainActor
private final class EventReminderAPISpy: LifeEventReminderFetching {
    let today: LifeCalendarDay
    let days: [String: LifeCalendarDay]
    private(set) var requestedDates: [String?] = []

    init(today: LifeCalendarDay, days: [String: LifeCalendarDay] = [:]) {
        self.today = today
        self.days = days
    }

    func fetchCalendarDay(date: String?) async throws -> LifeCalendarDay {
        requestedDates.append(date)
        guard let date else { return today }
        return days[date] ?? LifeCalendarDay(
            localDate: date,
            timeZoneIdentifier: today.timeZoneIdentifier,
            events: []
        )
    }
}

@MainActor
private final class EventReminderSchedulerSpy: LifeEventReminderScheduling {
    let isAuthorized: Bool
    private(set) var replacements: [[LifeEventReminder]] = []

    init(isAuthorized: Bool = true) {
        self.isAuthorized = isAuthorized
    }

    func requestAuthorization() async throws -> Bool { isAuthorized }

    func replaceEventReminders(_ reminders: [LifeEventReminder]) async throws {
        replacements.append(reminders)
    }
}
