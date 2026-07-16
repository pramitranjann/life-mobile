import Foundation
@testable import PRLifeKit

final class FakeRecorder: AudioRecording, @unchecked Sendable {
    var isRecording = false
    var startError: RecordingError?
    var fileName = "capture-1.m4a"
    var duration: TimeInterval = 12
    var selectedInputRoute: AudioInputRoute? = .init(
        identifier: "built-in-mic",
        name: "iPhone Microphone",
        portType: "BuiltInMic"
    )
    private(set) var stopCallCount = 0
    var suspendStart = false
    private(set) var isStartSuspended = false
    private var startContinuation: CheckedContinuation<Void, Never>?

    func start() async throws -> String {
        if let e = startError { throw e }
        if suspendStart {
            await withCheckedContinuation { continuation in
                isStartSuspended = true
                startContinuation = continuation
            }
            isStartSuspended = false
        }
        isRecording = true
        return fileName
    }

    func resumeStart() {
        startContinuation?.resume()
        startContinuation = nil
    }

    func stop() async -> TimeInterval {
        stopCallCount += 1
        isRecording = false
        return duration
    }
}
