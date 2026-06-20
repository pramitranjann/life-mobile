import Foundation
import Speech
import AVFoundation
import PRLifeKit

final class SpeechTranscriber: Transcribing, @unchecked Sendable {
    func transcribe(fileName: String) async throws -> String {
        let authorized = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard authorized else { throw TranscriptionError.permissionDenied }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        let url = AVAudioRecorderService.capturesDir.appendingPathComponent(fileName)
        let request = SFSpeechURLRecognitionRequest(url: url)
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        } else {
            // Spec: do not silently fall back to cloud. Keep audio, surface failure.
            throw TranscriptionError.recognizerUnavailable
        }

        return try await withCheckedThrowingContinuation { cont in
            // Guard against double-resume: the callback fires on partial results (no
            // isFinal, no error), on the final result, and can theoretically fire again
            // with an error even after isFinal. A nonisolated var is safe here because
            // SFSpeechRecognitionTask callbacks are serialised on a single queue.
            var hasResumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !hasResumed else { return }
                if let error {
                    hasResumed = true
                    cont.resume(throwing: TranscriptionError.systemError("\(error)"))
                    return
                }
                guard let result, result.isFinal else { return }
                hasResumed = true
                let text = result.bestTranscription.formattedString
                if text.isEmpty {
                    cont.resume(throwing: TranscriptionError.emptyTranscript)
                } else {
                    cont.resume(returning: text)
                }
            }
        }
    }
}
