import Foundation
import AVFoundation
import PRLifeKit

final class AVAudioRecorderService: NSObject, AudioRecording, @unchecked Sendable {
    private var recorder: AVAudioRecorder?
    private(set) var isRecording = false

    static var capturesDir: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("captures", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.none]
        )
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.none],
            ofItemAtPath: dir.path
        )
        return dir
    }

    func start() async throws -> String {
        let granted = await withCheckedContinuation { c in
            AVAudioApplication.requestRecordPermission { c.resume(returning: $0) }
        }
        guard granted else { throw RecordingError.permissionDenied }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.allowBluetooth, .allowBluetoothA2DP]
            )
            try session.setActive(true)
        } catch { throw RecordingError.sessionFailed("\(error)") }

        let name = "capture-\(UUID().uuidString).m4a"
        let url = Self.capturesDir.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [
                .protectionKey: FileProtectionType.none
            ])
        } else {
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.none],
                ofItemAtPath: url.path
            )
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.prepareToRecord()
            guard rec.record() else {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                throw RecordingError.sessionFailed("Recording could not start.")
            }
            recorder = rec
            isRecording = rec.isRecording
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
