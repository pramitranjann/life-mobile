import Foundation
import SwiftData
import WidgetKit
import PRLifeKit

extension Notification.Name {
    static let openPRLifeSettings = Notification.Name("openPRLifeSettings")
}

/// Process-wide capture stack, built once from persistent config. Used by both the
/// UI and App Intents so every entry point shares one coordinator/store/activity.
@MainActor
final class CaptureEnvironment {
    static let shared = CaptureEnvironment()
    static let captureStateDidChange = Notification.Name("CaptureEnvironment.captureStateDidChange")

    let container: ModelContainer
    let store: SwiftDataCaptureStore
    let coordinator: CaptureCoordinator
    let api: LifeAPIClient
    let activity = LiveActivityController()
    private var stopMonitorTask: Task<Void, Never>?

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
        coordinator = CaptureCoordinator(store: store, recorder: AVAudioRecorderService(),
                                         transcriber: SpeechTranscriber(), api: api, gate: gate)

        CaptureActionRouter.start = { ctx in
            CaptureControlChannel.clearStopRequest()
            await self.coordinator.handle(.startCapture(context: ctx))
            if self.coordinator.isRecording {
                self.beginStopRequestMonitoring()
                self.activity.start(context: ctx)
            }
            self.publishCaptureStateChange()
        }
        CaptureActionRouter.stop = {
            await self.stopCaptureFromAnySurface()
        }
    }

    func handleDeepLink(_ url: URL) async {
        guard url.scheme == "prlife" else { return }

        switch url.host(percentEncoded: false) {
        case "capture":
            CaptureControlChannel.clearStopRequest()
            let context = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "context" })?
                .value
                .flatMap(CaptureContext.init(rawValue:))
                ?? .quick
            await coordinator.handle(.startCapture(context: context))
            if coordinator.isRecording {
                beginStopRequestMonitoring()
                activity.start(context: context)
            }
            publishCaptureStateChange()
        case "stop":
            await stopCaptureFromAnySurface()
        case "settings":
            NotificationCenter.default.post(name: .openPRLifeSettings, object: nil)
        default:
            return
        }
    }

    private func beginStopRequestMonitoring() {
        stopMonitorTask?.cancel()
        let startedAt = Date()
        stopMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                guard CaptureControlChannel.stopRequested(since: startedAt) else { continue }
                CaptureControlChannel.clearStopRequest()
                await self.stopCaptureFromAnySurface()
                return
            }
        }
    }

    private func stopCaptureFromAnySurface() async {
        stopMonitorTask?.cancel()
        stopMonitorTask = nil
        await activity.update("SAVING_", phase: .processing, contextName: "Auto-uploading")
        await coordinator.handle(.stopCapture)
        await activity.end(finalLabel: "RECORDING SAVED_",
                           finalPhase: .saved,
                           finalContextName: "Ready for next capture",
                           dismissAfter: 4)
        publishCaptureStateChange()
    }

    private func publishCaptureStateChange() {
        NotificationCenter.default.post(name: Self.captureStateDidChange, object: nil)
        WidgetCenter.shared.reloadTimelines(ofKind: "PRLifeUpcoming")
    }
}
