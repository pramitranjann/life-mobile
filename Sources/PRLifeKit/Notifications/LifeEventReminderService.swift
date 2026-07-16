import Combine
import Foundation

public struct LifeEventReminder: Equatable, Sendable {
    public let id: String
    public let eventID: String
    public let localDate: String
    public let title: String
    public let body: String
    public let fireDate: Date
    public let isTimeSensitive: Bool

    public init(
        id: String,
        eventID: String,
        localDate: String,
        title: String,
        body: String,
        fireDate: Date,
        isTimeSensitive: Bool = false
    ) {
        self.id = id
        self.eventID = eventID
        self.localDate = localDate
        self.title = title
        self.body = body
        self.fireDate = fireDate
        self.isTimeSensitive = isTimeSensitive
    }
}

@MainActor
public protocol LifeEventReminderFetching {
    func fetchCalendarDay(date: String?) async throws -> LifeCalendarDay
}

@MainActor
public protocol LifeEventReminderScheduling: AnyObject {
    func requestAuthorization() async throws -> Bool
    func replaceEventReminders(_ reminders: [LifeEventReminder]) async throws
}

@MainActor
public final class LifeEventReminderService: ObservableObject {
    @Published public private(set) var lastError: String?

    private let api: LifeEventReminderFetching
    private let scheduler: LifeEventReminderScheduling
    private let lookAheadDays: Int
    private let settingsProvider: @MainActor () -> LifeNotificationSettings
    private let leadTimeOverride: TimeInterval?
    private let maximumReminders: Int
    private var isRefreshing = false

    public init(
        api: LifeEventReminderFetching,
        scheduler: LifeEventReminderScheduling,
        lookAheadDays: Int = 7,
        leadTime: TimeInterval? = nil,
        maximumReminders: Int = 50,
        settingsProvider: @escaping @MainActor () -> LifeNotificationSettings = { .default }
    ) {
        self.api = api
        self.scheduler = scheduler
        self.lookAheadDays = max(1, lookAheadDays)
        self.leadTimeOverride = leadTime.map { max(0, $0) }
        self.maximumReminders = min(max(1, maximumReminders), 50)
        self.settingsProvider = settingsProvider
    }

    /// Refreshes the next week of website calendar events whenever the phone app launches
    /// or returns to the foreground. Once scheduled, reminders fire even if the app closes.
    public func refresh(now: Date = Date()) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            _ = try await synchronize(now: now)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            NSLog("[PRLife][event-reminders] refresh failed: %@", "\(error)")
        }
    }

    @discardableResult
    public func synchronize(now: Date = Date()) async throws -> Int {
        let settings = settingsProvider()
        guard settings.calendarRemindersEnabled else {
            try await scheduler.replaceEventReminders([])
            return 0
        }
        let authorized = try await scheduler.requestAuthorization()
        guard authorized else { return 0 }

        let today = try await api.fetchCalendarDay(date: nil)
        var events = today.events

        if lookAheadDays > 1 {
            for offset in 1..<lookAheadDays {
                guard let localDate = Self.addingDays(offset, to: today.localDate) else { continue }
                events += try await api.fetchCalendarDay(date: localDate).events
            }
        }

        let reminders = Self.makeReminders(
            from: events,
            timeZoneIdentifier: today.timeZoneIdentifier,
            now: now,
            leadTime: leadTimeOverride ?? settings.calendarLeadTime.timeInterval,
            limit: maximumReminders,
            allDayReminderMinutes: settings.allDayReminderMinutes,
            quietHoursEnabled: settings.quietHoursEnabled,
            quietHoursStartMinutes: settings.quietHoursStartMinutes,
            quietHoursEndMinutes: settings.quietHoursEndMinutes,
            timeSensitiveEnabled: settings.timeSensitiveEnabled
        )
        try await scheduler.replaceEventReminders(reminders)
        return reminders.count
    }

    static func makeReminders(
        from events: [LifeEvent],
        timeZoneIdentifier: String,
        now: Date,
        leadTime: TimeInterval,
        limit: Int,
        allDayReminderMinutes: Int = 9 * 60,
        quietHoursEnabled: Bool = false,
        quietHoursStartMinutes: Int = 22 * 60,
        quietHoursEndMinutes: Int = 7 * 60,
        timeSensitiveEnabled: Bool = false,
        quietHoursCalendar: Calendar = .current
    ) -> [LifeEventReminder] {
        var seen = Set<String>()
        let reminders = events.compactMap { event -> LifeEventReminder? in
            guard seen.insert(event.id).inserted else { return nil }

            let fireDate: Date
            let body: String
            let isTimeSensitive: Bool
            if event.allDay {
                guard let allDayFire = date(
                    for: event.localDate,
                    minutesAfterMidnight: allDayReminderMinutes,
                    timeZoneIdentifier: timeZoneIdentifier
                ), allDayFire > now else { return nil }
                fireDate = allDayFire
                body = event.location.map { "All-day event today · \($0)" } ?? "All-day event today"
                isTimeSensitive = false
            } else {
                guard let start = event.start, start > now else { return nil }
                fireDate = max(start.addingTimeInterval(-leadTime), now.addingTimeInterval(2))
                let minutes = Int(leadTime / 60)
                let timing: String
                if minutes == 60 {
                    timing = "Starts in 1 hour"
                } else if minutes > 0 {
                    timing = "Starts in \(minutes) minutes"
                } else {
                    timing = "Starting now"
                }
                body = event.location.map { "\(timing) · \($0)" } ?? timing
                let untilStart = start.timeIntervalSince(fireDate)
                isTimeSensitive = timeSensitiveEnabled && untilStart >= 0 && untilStart <= 60 * 60
            }

            let quietSettings = LifeNotificationSettings(
                quietHoursEnabled: quietHoursEnabled,
                quietHoursStartMinutes: quietHoursStartMinutes,
                quietHoursEndMinutes: quietHoursEndMinutes
            )
            guard !quietSettings.isQuietHour(fireDate, calendar: quietHoursCalendar) || isTimeSensitive else {
                return nil
            }

            let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            return LifeEventReminder(
                id: "prlife.event.\(event.id)",
                eventID: event.id,
                localDate: event.localDate,
                title: title.flatMap { $0.isEmpty ? nil : $0 } ?? "Upcoming event",
                body: body,
                fireDate: fireDate,
                isTimeSensitive: isTimeSensitive
            )
        }

        return Array(reminders.sorted { $0.fireDate < $1.fireDate }.prefix(max(0, limit)))
    }

    static func addingDays(_ days: Int, to localDate: String) -> String? {
        guard let base = date(
            for: localDate,
            minutesAfterMidnight: 12 * 60,
            timeZoneIdentifier: "GMT"
        ) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let result = calendar.date(byAdding: .day, value: days, to: base) else { return nil }
        let components = calendar.dateComponents([.year, .month, .day], from: result)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return nil
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func date(
        for localDate: String,
        minutesAfterMidnight: Int,
        timeZoneIdentifier: String
    ) -> Date? {
        let values = localDate.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let validMinutes = min(max(minutesAfterMidnight, 0), 24 * 60 - 1)
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: values[0],
            month: values[1],
            day: values[2],
            hour: validMinutes / 60,
            minute: validMinutes % 60
        ))
    }
}

extension LifeAPIClient: LifeEventReminderFetching {}
