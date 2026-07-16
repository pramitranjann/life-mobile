import Foundation
import UserNotifications

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
public final class UserNotificationPresenter: NSObject, LifeNotificationScheduling, LifeEventReminderScheduling {
    public static let programApplicationCategory = "PRLIFE_PROGRAM_APPLICATION"
    public static let calendarEventCategory = "PRLIFE_CALENDAR_EVENT"
    private static let calendarEventIdentifierPrefix = "prlife.event."

    private let center: UNUserNotificationCenter
    private let calendarDestinationURL: @MainActor (LifeEventReminder) -> URL?

    public init(
        center: UNUserNotificationCenter = .current(),
        calendarDestinationURL: @escaping @MainActor (LifeEventReminder) -> URL? = { _ in nil }
    ) {
        self.center = center
        self.calendarDestinationURL = calendarDestinationURL
        super.init()
        center.delegate = self
        registerCategories()
    }

    public func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    public func requestAuthorization() async throws -> Bool {
        let status = await authorizationStatus()
        if status == .authorized || status == .provisional { return true }
#if os(iOS)
        if status == .ephemeral { return true }
#endif
        guard status == .notDetermined else { return false }
        return try await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    public func schedule(_ notification: LifeNotification, isTimeSensitive: Bool) async throws {
        async let pending = center.pendingNotificationRequests()
        async let delivered = center.deliveredNotifications()
        let existingIDs = Set(await pending.map(\.identifier) + delivered.map { $0.request.identifier })
        guard !existingIDs.contains(notification.id) else { return }

        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.categoryIdentifier = Self.programApplicationCategory
        content.threadIdentifier = "prlife.application-alerts"
        if isTimeSensitive {
            content.interruptionLevel = .timeSensitive
        }
        if let url = notification.url {
            content.userInfo["url"] = url.absoluteString
        }
        let request = UNNotificationRequest(identifier: notification.id, content: content, trigger: nil)
        try await center.add(request)
    }

    public func replaceEventReminders(_ reminders: [LifeEventReminder]) async throws {
        let desiredIDs = Set(reminders.map(\.id))

        // Adding a request with an existing identifier updates a rescheduled event in place.
        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.categoryIdentifier = Self.calendarEventCategory
            content.threadIdentifier = "prlife.calendar-reminders"
            if reminder.isTimeSensitive {
                content.interruptionLevel = .timeSensitive
            }
            content.userInfo["eventID"] = reminder.eventID
            content.userInfo["localDate"] = reminder.localDate
            if let url = calendarDestinationURL(reminder) {
                content.userInfo["url"] = url.absoluteString
            }

            let interval = max(1, reminder.fireDate.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
            try await center.add(request)
        }

        let pending = await center.pendingNotificationRequests()
        let staleIDs = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.calendarEventIdentifierPrefix) && !desiredIDs.contains($0) }
        if !staleIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIDs)
        }
    }

    public func scheduledEventReminderCount() async -> Int {
        await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.calendarEventIdentifierPrefix) }
            .count
    }

    /// A standard titled, audible notification is eligible for Siri announcements
    /// when the user enables Announce Notifications for PR Life in iOS Settings.
    public func sendTestNotification() async throws {
        guard try await requestAuthorization() else {
            throw UserNotificationPresenterError.authorizationDenied
        }
        let content = UNMutableNotificationContent()
        content.title = "PR Life test"
        content.body = "Notifications are ready."
        content.sound = .default
        content.categoryIdentifier = Self.programApplicationCategory
        content.threadIdentifier = "prlife.tests"
        let request = UNNotificationRequest(
            identifier: "prlife.test.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try await center.add(request)
    }

    private func registerCategories() {
        let application = UNNotificationCategory(
            identifier: Self.programApplicationCategory,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        let calendar = UNNotificationCategory(
            identifier: Self.calendarEventCategory,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([application, calendar])
    }
}

public enum UserNotificationPresenterError: LocalizedError, Equatable {
    case authorizationDenied

    public var errorDescription: String? {
        "Notification permission is not enabled."
    }
}

extension UserNotificationPresenter: UNUserNotificationCenterDelegate {
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard let rawURL = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: rawURL) else {
            completionHandler()
            return
        }

        Task { @MainActor in
#if os(iOS)
            _ = await UIApplication.shared.open(url)
#elseif os(macOS)
            NSWorkspace.shared.open(url)
#endif
            completionHandler()
        }
    }
}
