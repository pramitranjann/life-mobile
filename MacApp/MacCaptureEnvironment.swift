import Foundation
import SwiftData
import Combine
import PRLifeKit

@MainActor
final class MacCaptureEnvironment: ObservableObject {
    static let shared = MacCaptureEnvironment()

    let container: ModelContainer
    let store: SwiftDataCaptureStore
    let coordinator: CaptureCoordinator
    let api: LifeAPIClient
    private let hotKeys = CarbonHotKeyManager()

    @Published private(set) var isRecording = false
    @Published private(set) var recordingContext: CaptureContext?

    private init() {
        let config = ModelConfiguration(groupContainer: .identifier(AppGroup.id))
        container = try! ModelContainer(for: CaptureEntity.self, configurations: config)
        store = SwiftDataCaptureStore(context: ModelContext(container))

        api = LifeAPIClient(configurationProvider: {
            let trimmed = KeychainConfig.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (URL(string: trimmed), KeychainConfig.token)
        })
        let gate = UploadGate(reachability: PathMonitorReachability(),
                              wifiOnly: UserDefaults.standard.bool(forKey: "wifiOnly"))
        coordinator = CaptureCoordinator(store: store, recorder: MacAudioRecorderService(),
                                         transcriber: SpeechTranscriber(), api: api, gate: gate)

        CaptureActionRouter.start = { [weak self] ctx in
            guard let self else { return }
            CaptureControlChannel.clearStopRequest()
            await self.coordinator.handle(.startCapture(context: ctx))
            self.isRecording = self.coordinator.isRecording
            self.recordingContext = self.coordinator.isRecording ? ctx : nil
        }
        CaptureActionRouter.stop = { [weak self] in
            guard let self else { return }
            await self.coordinator.handle(.stopCapture)
            self.isRecording = false
            self.recordingContext = nil
        }
    }

    func startHotKeys() {
        hotKeys.register(HotKeyBinding.defaults) { context in
            Task { @MainActor in
                let env = MacCaptureEnvironment.shared
                if env.isRecording {
                    await CaptureActionRouter.stop?()
                } else {
                    await CaptureActionRouter.start?(context)
                }
            }
        }
    }

    /// Toggle entry point used by popover buttons / menu items.
    func toggleCapture(_ context: CaptureContext) {
        Task {
            if isRecording { await CaptureActionRouter.stop?() }
            else { await CaptureActionRouter.start?(context) }
        }
    }

    func stopCapture() { Task { await CaptureActionRouter.stop?() } }
}
