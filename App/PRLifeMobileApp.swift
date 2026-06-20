import SwiftUI
import SwiftData
import PRLifeKit

@main
struct PRLifeMobileApp: App {
    let container: ModelContainer
    @State private var coordinator: CaptureCoordinator
    private let store: SwiftDataCaptureStore

    init() {
        let container = try! ModelContainer(for: CaptureEntity.self)
        self.container = container
        let store = SwiftDataCaptureStore(context: ModelContext(container))
        self.store = store

        let base = URL(string: KeychainConfig.baseURL ?? "http://localhost:3000")!
        let api = LifeAPIClient(baseURL: base, token: KeychainConfig.token ?? "")
        let gate = UploadGate(reachability: PathMonitorReachability(),
                              wifiOnly: UserDefaults.standard.bool(forKey: "wifiOnly"))
        _coordinator = State(initialValue: CaptureCoordinator(
            store: store, recorder: AVAudioRecorderService(),
            transcriber: SpeechTranscriber(), api: api, gate: gate))
    }

    var body: some Scene {
        WindowGroup {
            MainView(coordinator: coordinator, store: store)
        }
        .modelContainer(container)
    }
}
