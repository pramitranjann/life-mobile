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

    private init() {
        // Prefer the shared App Group container (paid accounts); fall back to the app-local
        // store when the App Group isn't provisioned (free Apple ID sideloads) so we don't crash.
        if let grouped = try? ModelContainer(for: CaptureEntity.self,
                                             configurations: ModelConfiguration(groupContainer: .identifier(AppGroup.id))) {
            container = grouped
        } else {
            container = try! ModelContainer(for: CaptureEntity.self)
        }
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
            await self.coordinator.handle(.startCapture(context: ctx))
            if self.coordinator.isRecording {
                self.activity.start(context: ctx)
            }
            self.publishCaptureStateChange()
        }
        CaptureActionRouter.stop = {
            await self.stopCaptureFromAnySurface()
        }

        CaptureControlChannel.observeStop { [weak self] in
            Task { await self?.stopCaptureFromAnySurface() }
        }
    }

    func handleDeepLink(_ url: URL) async {
        guard url.scheme == "prlife" else { return }

        switch url.host(percentEncoded: false) {
        case "capture":
            let context = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "context" })?
                .value
                .flatMap(CaptureContext.init(rawValue:))
                ?? .quick
            await coordinator.handle(.startCapture(context: context))
            if coordinator.isRecording {
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

    private func stopCaptureFromAnySurface() async {
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
