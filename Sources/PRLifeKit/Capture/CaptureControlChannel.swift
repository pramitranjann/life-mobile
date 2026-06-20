import Foundation

/// Shared app-group control flags used by the app and widget extension to coordinate
/// capture actions when they are not running in the same process.
public enum CaptureControlChannel {
    private static let suiteName = "group.com.pramitranjan.prlife"
    private static let stopRequestKey = "capture.stopRequestAt"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    public static func requestStop(now: Date = .now) {
        defaults?.set(now.timeIntervalSince1970, forKey: stopRequestKey)
    }

    public static func clearStopRequest() {
        defaults?.removeObject(forKey: stopRequestKey)
    }

    public static func stopRequested(since date: Date) -> Bool {
        guard let interval = defaults?.object(forKey: stopRequestKey) as? Double else {
            return false
        }
        return interval > date.timeIntervalSince1970
    }
}
