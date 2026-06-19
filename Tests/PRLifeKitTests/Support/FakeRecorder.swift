import Foundation
@testable import PRLifeKit

final class FakeRecorder: AudioRecording, @unchecked Sendable {
    var isRecording = false
    var startError: RecordingError?
    var fileName = "capture-1.m4a"
    var duration: TimeInterval = 12

    func start() async throws -> String {
        if let e = startError { throw e }
        isRecording = true
        return fileName
    }
    func stop() async -> TimeInterval { isRecording = false; return duration }
}
