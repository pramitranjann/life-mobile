import Foundation
import PRLifeKit

/// Date/time helpers for the dashboard, all in the user's current timezone.
enum LifeFormatting {
    static func todayLocalDate(_ now: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: now)
    }

    /// "14:00" style clock for an event start; "All day" when applicable.
    static func timeLabel(for event: LifeEvent) -> String {
        if event.allDay { return "All day" }
        guard let start = event.start else { return "" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: start)
    }

    /// "14:00 → 15:30" range when both ends exist; otherwise just the start.
    static func rangeLabel(for event: LifeEvent) -> String {
        if event.allDay { return "All day" }
        guard let start = event.start else { return "" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let startStr = f.string(from: start)
        guard let end = event.end else { return startStr }
        return "\(startStr) → \(f.string(from: end))"
    }

    /// Minutes until an event's start, when in the future and within the day.
    static func minutesUntil(_ event: LifeEvent, now: Date = Date()) -> Int? {
        guard let start = event.start else { return nil }
        let seconds = start.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        return Int(seconds / 60)
    }

    /// Compact countdown like "22m" or "1h 5m".
    static func countdownLabel(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    /// "Thursday" + "19 JUNE 2026" pair for the window heading.
    static func headingParts(_ now: Date = Date()) -> (weekday: String, date: String) {
        let weekday = DateFormatter()
        weekday.dateFormat = "EEEE"
        let date = DateFormatter()
        date.dateFormat = "d MMMM yyyy"
        return (weekday.string(from: now), date.string(from: now).uppercased())
    }
}
