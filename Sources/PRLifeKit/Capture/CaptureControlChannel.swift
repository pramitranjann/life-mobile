import Foundation
import CoreFoundation

/// Cross-process capture control. Posts/observes a Darwin notification, which works
/// across the app and its extensions without touching App Group preferences.
public enum CaptureControlChannel {
    private static let darwinStopName = "com.pramitranjan.prlife.capture.stop"

    nonisolated(unsafe) private static var stopHandler: (() -> Void)?
    private static let observerToken = UnsafeRawPointer(bitPattern: 0x50524C66)!

    /// Request a cross-process stop using Darwin notifications only.
    public static func requestStop(now _: Date = .now) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(darwinStopName as CFString),
            nil, nil, true)
    }

    public static func clearStopRequest() {}

    public static func stopRequested(since date: Date) -> Bool { false }

    /// Register a process-wide observer for cross-process stop requests.
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
