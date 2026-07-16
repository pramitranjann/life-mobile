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

/// Platform-neutral description of the microphone selected for a recording.
/// AVFoundation-backed recorders can populate this from the active input port.
public struct AudioInputRoute: Codable, Equatable, Sendable {
    public var identifier: String
    public var name: String
    public var portType: String

    public init(identifier: String, name: String, portType: String) {
        self.identifier = identifier
        self.name = name
        self.portType = portType
    }
}

public protocol AudioRecording: AnyObject, Sendable {
    /// Starts recording, returns the audio file name (relative to captures dir).
    func start() async throws -> String
    /// Stops recording, returns final duration in seconds.
    func stop() async -> TimeInterval
    var isRecording: Bool { get }
    /// The input selected by the platform recorder after `start()` succeeds.
    var selectedInputRoute: AudioInputRoute? { get }
}

public extension AudioRecording {
    /// Existing recorders remain source-compatible until they can report a route.
    var selectedInputRoute: AudioInputRoute? { nil }
}
