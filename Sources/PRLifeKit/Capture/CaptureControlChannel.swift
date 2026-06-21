import Foundation
import CoreFoundation

/// Cross-process capture control. Posts/observes a **Darwin notification**, which works
/// across the app and its extensions WITHOUT an App Group or any entitlement — so it
/// functions on free Apple ID sideloads. The App-Group `UserDefaults` flag is kept as a
/// secondary fallback for processes that poll (e.g. a paid macOS build).
public enum CaptureControlChannel {
    private static let suiteName = "group.com.pramitranjan.prlife"
    private static let stopRequestKey = "capture.stopRequestAt"
    private static let darwinStopName = "com.pramitranjan.prlife.capture.stop"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    nonisolated(unsafe) private static var stopHandler: (() -> Void)?
    private static let observerToken = UnsafeRawPointer(bitPattern: 0x50524C66)!

    /// Request a cross-process stop. Posts a Darwin notification (App-Group-free) AND sets
    /// the App-Group flag (for any poller). Safe to call from the widget extension process.
    public static func requestStop(now: Date = .now) {
        defaults?.set(now.timeIntervalSince1970, forKey: stopRequestKey)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(darwinStopName as CFString),
            nil, nil, true)
    }

    public static func clearStopRequest() {
        defaults?.removeObject(forKey: stopRequestKey)
    }

    public static func stopRequested(since date: Date) -> Bool {
        guard let interval = defaults?.object(forKey: stopRequestKey) as? Double else { return false }
        return interval > date.timeIntervalSince1970
    }

    /// Register a process-wide observer for cross-process stop requests (Darwin-based, no
    /// App Group needed). `handler` runs on the main queue. Call once at app launch.
    public static func observeStop(_ handler: @escaping () -> Void) {
        stopHandler = handler
        let callback: CFNotificationCallback = { _, _, _, _, _ in
            DispatchQueue.main.async { CaptureControlChannel.stopHandler?() }
        }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observerToken,
            callback,
            darwinStopName as CFString,
            nil,
            .deliverImmediately)
    }
}
