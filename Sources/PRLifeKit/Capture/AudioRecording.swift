import Foundation

public enum RecordingError: Error, Equatable, LocalizedError {
    case permissionDenied
    case sessionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission was denied."
        case .sessionFailed(let message):
            return message
        }
    }
}

public protocol AudioRecording: AnyObject, Sendable {
    /// Starts recording, returns the audio file name (relative to captures dir).
    func start() async throws -> String
    /// Stops recording, returns final duration in seconds.
    func stop() async -> TimeInterval
    var isRecording: Bool { get }
}
