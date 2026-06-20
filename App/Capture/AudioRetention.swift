import Foundation
import PRLifeKit

@MainActor
struct AudioRetention {
    let store: SwiftDataCaptureStore
    /// Deletes audio files for captures uploaded > 24h ago; keeps transcript + record.
    func purge(now: Date = .now) {
        let cutoff = now.addingTimeInterval(-24 * 3600)
        for rec in store.all()
            where rec.status == .done && rec.createdAt < cutoff && rec.audioFileName != nil {
            let url = AVAudioRecorderService.capturesDir.appendingPathComponent(rec.audioFileName!)
            try? FileManager.default.removeItem(at: url)
            store.update(id: rec.id) { $0.audioFileName = nil }
        }
    }
}
