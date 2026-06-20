import Foundation

public enum TranscriptionError: Error, Equatable, LocalizedError {
    case permissionDenied
    case recognizerUnavailable
    case emptyTranscript
    case systemError(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Speech recognition permission was denied."
        case .recognizerUnavailable:
            return "On-device speech recognition is unavailable for the current device or language."
        case .emptyTranscript:
            return "No speech was detected in the recording."
        case .systemError(let message):
            return message
        }
    }
}

public protocol Transcribing: AnyObject, Sendable {
    func transcribe(fileName: String) async throws -> String
}
