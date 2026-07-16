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

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
    }

    public func requestAuthorization() async throws -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        if status == .authorized || status == .provisional { return true }
#if os(iOS)
        if status == .ephemeral { return true }
#endif
        guard status == .notDetermined else { return false }
        return try await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    public func schedule(_ notification: LifeNotification) async throws {
        async let pending = center.pendingNotificationRequests()
        async let delivered = center.deliveredNotifications()
        let existingIDs = Set(await pending.map(\.identifier) + delivered.map { $0.request.identifier })
        guard !existingIDs.contains(notification.id) else { return }

        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.categoryIdentifier = Self.programApplicationCategory
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
            content.userInfo["eventID"] = reminder.eventID
            content.userInfo["localDate"] = reminder.localDate

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
        defer { completionHandler() }
        guard let rawURL = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: rawURL) else { return }

        Task { @MainActor in
#if os(iOS)
            await UIApplication.shared.open(url)
#elseif os(macOS)
            NSWorkspace.shared.open(url)
#endif
        }
    }
}
