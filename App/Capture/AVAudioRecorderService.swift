import Foundation
import AVFoundation
import PRLifeKit

final class AVAudioRecorderService: NSObject, AudioRecording, @unchecked Sendable {
    private var recorder: AVAudioRecorder?
    private(set) var isRecording = false

    static var capturesDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func start() async throws -> String {
        let granted = await withCheckedContinuation { c in
            AVAudioApplication.requestRecordPermission { c.resume(returning: $0) }
        }
        guard granted else { throw RecordingError.permissionDenied }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch { throw RecordingError.sessionFailed("\(error)") }

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
            rec.record()
            recorder = rec; isRecording = true
            return name
        } catch {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            throw RecordingError.sessionFailed("\(error)")
        }
    }

    func stop() async -> TimeInterval {
        let d = recorder?.currentTime ?? 0
        recorder?.stop(); recorder = nil; isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return d
    }
}
