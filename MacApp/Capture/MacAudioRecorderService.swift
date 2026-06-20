import Foundation
import AVFoundation
import PRLifeKit

/// macOS desktop-mic recorder. Unlike iOS there is no AVAudioSession; AVAudioRecorder
/// records directly. Mic permission is requested via AVCaptureDevice.
final class MacAudioRecorderService: NSObject, AudioRecording, @unchecked Sendable {
    private var recorder: AVAudioRecorder?
    private(set) var isRecording = false

    static var capturesDir: URL {
        let dir = AppGroup.containerURL.appendingPathComponent("captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func start() async throws -> String {
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: granted = true
        case .notDetermined:
            granted = await AVCaptureDevice.requestAccess(for: .audio)
        default: granted = false
        }
        guard granted else { throw RecordingError.permissionDenied }

        let name = "capture-\(UUID().uuidString).m4a"
        let url = Self.capturesDir.appendingPathComponent(name)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.prepareToRecord()
            guard rec.record() else { throw RecordingError.sessionFailed("Recording could not start.") }
            recorder = rec
            isRecording = rec.isRecording
            return name
        } catch let error as RecordingError {
            throw error
        } catch {
            throw RecordingError.sessionFailed("\(error)")
        }
    }

    func stop() async -> TimeInterval {
        let d = recorder?.currentTime ?? 0
        recorder?.stop(); recorder = nil; isRecording = false
        return d
    }
}
