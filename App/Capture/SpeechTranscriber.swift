import Foundation
import Speech
import AVFoundation
import PRLifeKit

/// Guarantees a CheckedContinuation is resumed exactly once across the
/// recognition callback (which can fire multiple times) and the timeout watchdog.
private final class ResumeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    var task: SFSpeechRecognitionTask?

    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if resumed { return false }
        resumed = true
        return true
    }
}

final class SpeechTranscriber: Transcribing, @unchecked Sendable {
    /// Hard ceiling so a stalled recognition can never wedge a capture in `.processing`.
    private let timeout: TimeInterval = 60

    func transcribe(fileName: String) async throws -> String {
        let authorized = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard authorized else { throw TranscriptionError.permissionDenied }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            // Spec: never silently fall back to cloud. Keep audio, surface failure.
            throw TranscriptionError.recognizerUnavailable
        }

        let url = AVAudioRecorderService.capturesDir.appendingPathComponent(fileName)
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true

        let box = ResumeBox()
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    if box.claim() { cont.resume(throwing: TranscriptionError.systemError("\(error)")) }
                    return
                }
                guard let result, result.isFinal else { return }   // ignore partials
                let text = result.bestTranscription.formattedString
                if box.claim() {
                    if text.isEmpty { cont.resume(throwing: TranscriptionError.emptyTranscript) }
                    else { cont.resume(returning: text) }
                }
            }
            box.task = task
            // Watchdog: if neither final nor error arrives in time, cancel and fail.
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if box.claim() {
                    box.task?.cancel()
                    cont.resume(throwing: TranscriptionError.systemError("transcription timed out"))
                }
            }
        }
    }
}
