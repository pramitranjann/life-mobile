import Combine
import Foundation

public struct LifeEventReminder: Equatable, Sendable {
    public let id: String
    public let eventID: String
    public let localDate: String
    public let title: String
    public let body: String
    public let fireDate: Date

    public init(
        id: String,
        eventID: String,
        localDate: String,
        title: String,
        body: String,
        fireDate: Date
    ) {
        self.id = id
        self.eventID = eventID
        self.localDate = localDate
        self.title = title
        self.body = body
        self.fireDate = fireDate
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
    private let leadTime: TimeInterval
    private let maximumReminders: Int
    private var isRefreshing = false

    public init(
        api: LifeEventReminderFetching,
        scheduler: LifeEventReminderScheduling,
        lookAheadDays: Int = 7,
        leadTime: TimeInterval = 10 * 60,
        maximumReminders: Int = 50
    ) {
        self.api = api
        self.scheduler = scheduler
        self.lookAheadDays = max(1, lookAheadDays)
        self.leadTime = max(0, leadTime)
        self.maximumReminders = min(max(1, maximumReminders), 50)
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
            leadTime: leadTime,
            limit: maximumReminders
        )
        try await scheduler.replaceEventReminders(reminders)
        return reminders.count
    }

    static func makeReminders(
        from events: [LifeEvent],
        timeZoneIdentifier: String,
        now: Date,
        leadTime: TimeInterval,
        limit: Int
    ) -> [LifeEventReminder] {
        var seen = Set<String>()
        let reminders = events.compactMap { event -> LifeEventReminder? in
            guard seen.insert(event.id).inserted else { return nil }

            let fireDate: Date
            let body: String
            if event.allDay {
                guard let allDayFire = date(
                    for: event.localDate,
                    hour: 9,
                    timeZoneIdentifier: timeZoneIdentifier
                ), allDayFire > now else { return nil }
                fireDate = allDayFire
                body = event.location.map { "All-day event today · \($0)" } ?? "All-day event today"
            } else {
                guard let start = event.start, start > now else { return nil }
                fireDate = max(start.addingTimeInterval(-leadTime), now.addingTimeInterval(2))
                let minutes = Int(leadTime / 60)
                let timing = minutes > 0 ? "Starts in \(minutes) minutes" : "Starting now"
                body = event.location.map { "\(timing) · \($0)" } ?? timing
            }

            let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            return LifeEventReminder(
                id: "prlife.event.\(event.id)",
                eventID: event.id,
                localDate: event.localDate,
                title: title.flatMap { $0.isEmpty ? nil : $0 } ?? "Upcoming event",
                body: body,
                fireDate: fireDate
            )
        }

        return Array(reminders.sorted { $0.fireDate < $1.fireDate }.prefix(max(0, limit)))
    }

    static func addingDays(_ days: Int, to localDate: String) -> String? {
        guard let base = date(for: localDate, hour: 12, timeZoneIdentifier: "GMT") else { return nil }
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
        hour: Int,
        timeZoneIdentifier: String
    ) -> Date? {
        let values = localDate.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: values[0],
            month: values[1],
            day: values[2],
            hour: hour
        ))
    }
}

extension LifeAPIClient: LifeEventReminderFetching {}
