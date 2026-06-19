import Foundation

public enum TranscriptionError: Error, Equatable {
    case permissionDenied
    case recognizerUnavailable
    case emptyTranscript
    case systemError(String)
}

public protocol Transcribing: AnyObject, Sendable {
    func transcribe(fileName: String) async throws -> String
}
