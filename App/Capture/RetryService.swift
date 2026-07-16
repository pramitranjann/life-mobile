import Foundation
import PRLifeKit

@MainActor
struct RetryService {
    let store: SwiftDataCaptureStore
    let coordinator: CaptureCoordinator

    /// Reconciles records orphaned by an app kill, then re-attempts eligible uploads.
    func sweep() async {
        for rec in store.all() {
            switch rec.status {
            case .recording, .processing:
                // Killed before a transcript existed. Mark failed/recoverable so it
                // surfaces and isn't stuck forever (audio file may still be on disk).
                store.update(id: rec.id) {
                    $0.status = .failed
                    $0.lastError = "interrupted before transcription"
                }
                await coordinator.retry(id: rec.id)
            case .uploading:
                // The app was killed while a durable write was in flight. Move it to
                // the retry state so the coordinator can preserve note/task semantics.
                store.update(id: rec.id) {
                    $0.status = .failed
                    $0.lastError = "interrupted during upload"
                }
                await coordinator.retry(id: rec.id)
            case .failed:
                guard rec.serverEntryId == nil else { continue }
                await coordinator.retry(id: rec.id)
            case .reviewing, .done:
                continue
            }
        }
    }
}
