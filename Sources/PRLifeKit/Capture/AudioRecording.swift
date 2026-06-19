import Foundation

public enum RecordingError: Error, Equatable { case permissionDenied, sessionFailed(String) }

public protocol AudioRecording: AnyObject, Sendable {
    /// Starts recording, returns the audio file name (relative to captures dir).
    func start() async throws -> String
    /// Stops recording, returns final duration in seconds.
    func stop() async -> TimeInterval
    var isRecording: Bool { get }
}
