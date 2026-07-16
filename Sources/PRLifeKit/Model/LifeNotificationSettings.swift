import Foundation

public enum LifeNotificationLeadTime: Int, Codable, CaseIterable, Identifiable, Sendable {
    case atTime = 0
    case tenMinutes = 600
    case thirtyMinutes = 1_800
    case oneHour = 3_600

    public var id: Int { rawValue }
    public var timeInterval: TimeInterval { TimeInterval(rawValue) }

    public var displayName: String {
        switch self {
        case .atTime: "At time"
        case .tenMinutes: "10 min"
        case .thirtyMinutes: "30 min"
        case .oneHour: "1 hour"
        }
    }
}

public struct LifeNotificationSettings: Codable, Equatable, Sendable {
    public var calendarRemindersEnabled: Bool
    public var applicationAlertsEnabled: Bool
    public var calendarLeadTime: LifeNotificationLeadTime
    /// Minutes after midnight in the calendar owner's local time.
    public var allDayReminderMinutes: Int
    public var quietHoursEnabled: Bool
    public var quietHoursStartMinutes: Int
    public var quietHoursEndMinutes: Int
    public var timeSensitiveEnabled: Bool

    public init(
        calendarRemindersEnabled: Bool = true,
        applicationAlertsEnabled: Bool = true,
        calendarLeadTime: LifeNotificationLeadTime = .tenMinutes,
        allDayReminderMinutes: Int = 9 * 60,
        quietHoursEnabled: Bool = false,
        quietHoursStartMinutes: Int = 22 * 60,
        quietHoursEndMinutes: Int = 7 * 60,
        timeSensitiveEnabled: Bool = false
    ) {
        self.calendarRemindersEnabled = calendarRemindersEnabled
        self.applicationAlertsEnabled = applicationAlertsEnabled
        self.calendarLeadTime = calendarLeadTime
        self.allDayReminderMinutes = Self.validMinute(allDayReminderMinutes)
        self.quietHoursEnabled = quietHoursEnabled
        self.quietHoursStartMinutes = Self.validMinute(quietHoursStartMinutes)
        self.quietHoursEndMinutes = Self.validMinute(quietHoursEndMinutes)
        self.timeSensitiveEnabled = timeSensitiveEnabled
    }

    public static let `default` = LifeNotificationSettings()

    public func isQuietHour(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard quietHoursEnabled else { return false }
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let start = Self.validMinute(quietHoursStartMinutes)
        let end = Self.validMinute(quietHoursEndMinutes)

        if start == end { return true }
        if start < end { return minute >= start && minute < end }
        return minute >= start || minute < end
    }

    private static func validMinute(_ value: Int) -> Int {
        min(max(value, 0), 24 * 60 - 1)
    }
}

public protocol LifeNotificationSettingsStoring: AnyObject {
    var settings: LifeNotificationSettings { get }
    func save(_ settings: LifeNotificationSettings)
}

public final class UserDefaultsLifeNotificationSettingsStore: LifeNotificationSettingsStoring, @unchecked Sendable {
    public static let storageKey = "lifeNotifications.settings.v1"

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = storageKey) {
        self.defaults = defaults
        self.key = key
    }

    public var settings: LifeNotificationSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(LifeNotificationSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    public func save(_ settings: LifeNotificationSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

public extension Notification.Name {
    static let lifeNotificationSettingsDidChange = Notification.Name(
        "LifeNotificationSettings.didChange"
    )
    static let lifeNotificationRefreshDidFinish = Notification.Name(
        "LifeNotificationSettings.refreshDidFinish"
    )
}
