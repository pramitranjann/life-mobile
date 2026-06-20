import Foundation
import SwiftData
import PRLifeKit

/// Process-wide capture stack, built once from persistent config. Used by both the
/// UI and App Intents so every entry point shares one coordinator/store/activity.
@MainActor
final class CaptureEnvironment {
    static let shared = CaptureEnvironment()

    let container: ModelContainer
    let store: SwiftDataCaptureStore
    let coordinator: CaptureCoordinator
    let activity = LiveActivityController()

    private init() {
        let config = ModelConfiguration(groupContainer: .identifier(AppGroup.id))
        container = try! ModelContainer(for: CaptureEntity.self, configurations: config)
        store = SwiftDataCaptureStore(context: ModelContext(container))

        let base = URL(string: KeychainConfig.baseURL ?? "http://localhost:3000")!
        let api = LifeAPIClient(baseURL: base, token: KeychainConfig.token ?? "")
        let gate = UploadGate(reachability: PathMonitorReachability(),
                              wifiOnly: UserDefaults.standard.bool(forKey: "wifiOnly"))
        coordinator = CaptureCoordinator(store: store, recorder: AVAudioRecorderService(),
                                         transcriber: SpeechTranscriber(), api: api, gate: gate)
    }
}
