@preconcurrency import AVFoundation
import Foundation

enum CaptureCue: Sendable {
    case start
    case stop
    case saved
    case failure
}

/// Plays short generated tones through the current output route. Recording is
/// started only after the start cue finishes, and every other cue is played only
/// after the recorder has finalized its file, so cues cannot enter captured audio.
@MainActor
final class CaptureCuePlayer: NSObject, @preconcurrency AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var completion: CheckedContinuation<Void, Never>?

    func play(_ cue: CaptureCue) async {
        finishPlayback()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(data: Self.waveData(for: cue))
            player.delegate = self
            player.volume = 0.24
            player.prepareToPlay()
            self.player = player

            guard player.play() else {
                finishPlayback()
                return
            }
            await withCheckedContinuation { completion = $0 }
        } catch {
            finishPlayback()
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finishPlayback()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        finishPlayback()
    }

    private func finishPlayback() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        completion?.resume()
        completion = nil
    }

    private static func waveData(for cue: CaptureCue) -> Data {
        let tones: [(frequency: Double, duration: Double)]
        switch cue {
        case .start: tones = [(660, 0.055), (0, 0.025), (880, 0.065)]
        case .stop: tones = [(740, 0.055), (0, 0.025), (520, 0.065)]
        case .saved: tones = [(784, 0.05), (0, 0.02), (1_046, 0.08)]
        case .failure: tones = [(294, 0.07), (0, 0.025), (220, 0.09)]
        }

        let sampleRate = 22_050
        var samples: [Int16] = []
        for tone in tones {
            let count = Int(Double(sampleRate) * tone.duration)
            for index in 0..<count {
                guard tone.frequency > 0 else {
                    samples.append(0)
                    continue
                }
                let progress = Double(index) / Double(max(count - 1, 1))
                let envelope = sin(.pi * progress)
                let value = sin(2 * .pi * tone.frequency * Double(index) / Double(sampleRate))
                samples.append(Int16(value * envelope * Double(Int16.max) * 0.34))
            }
        }

        let pcmByteCount = samples.count * MemoryLayout<Int16>.size
        var data = Data()
        data.appendASCII("RIFF")
        data.appendLittleEndian(UInt32(36 + pcmByteCount))
        data.appendASCII("WAVEfmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(sampleRate * 2))
        data.appendLittleEndian(UInt16(2))
        data.appendLittleEndian(UInt16(16))
        data.appendASCII("data")
        data.appendLittleEndian(UInt32(pcmByteCount))
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
