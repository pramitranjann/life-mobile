import Foundation
import UserNotifications

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
public final class UserNotificationPresenter: NSObject, LifeNotificationScheduling {
    public static let programApplicationCategory = "PRLIFE_PROGRAM_APPLICATION"

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
