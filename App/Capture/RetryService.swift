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
            case .uploading, .failed:
                // Have a transcript but never reached .done — retry the upload.
                guard let transcript = rec.transcript, rec.serverEntryId == nil else { continue }
                await coordinator.upload(id: rec.id, content: transcript,
                                         projectSlug: rec.context.projectSlug)
            case .done:
                continue
            }
        }
    }
}
