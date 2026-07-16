import Foundation

/// A calendar event read from `GET /api/life/calendar`. `startTime`/`endTime` are kept
/// as raw ISO8601 strings (trivial Codable) with parsed `Date` exposed via `start`/`end`.
public struct LifeEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String?
    public let startTime: String?
    public let endTime: String?
    public let allDay: Bool
    public let location: String?
    public let localDate: String

    enum CodingKeys: String, CodingKey {
        case id, title, location
        case startTime = "start_time"
        case endTime = "end_time"
        case allDay = "all_day"
        case localDate = "local_date"
    }

    public init(id: String, title: String?, startTime: String?, endTime: String?,
                allDay: Bool, location: String?, localDate: String) {
        self.id = id; self.title = title; self.startTime = startTime; self.endTime = endTime
        self.allDay = allDay; self.location = location; self.localDate = localDate
    }

    public var start: Date? { LifeEvent.parseISO(startTime) }
    public var end: Date? { LifeEvent.parseISO(endTime) }

    /// Tolerant of both plain and fractional-second internet timestamps.
    static func parseISO(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}

/// One owner-local calendar day returned by `GET /api/life/calendar`.
public struct LifeCalendarDay: Codable, Equatable, Sendable {
    public let localDate: String
    public let timeZoneIdentifier: String
    public let events: [LifeEvent]

    enum CodingKeys: String, CodingKey {
        case localDate, events
        case timeZoneIdentifier = "timezone"
    }

    public init(localDate: String, timeZoneIdentifier: String, events: [LifeEvent]) {
        self.localDate = localDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.events = events
    }
}
