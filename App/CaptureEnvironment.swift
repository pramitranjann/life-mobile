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
        // App-local SwiftData store. We deliberately do NOT use a `groupContainer:`
        // (App Group) configuration: on a free Apple ID the App Group isn't provisioned
        // and SwiftData *traps* (assertionFailure, uncatchable by try?) rather than
        // throwing, which crashed the app on launch. Nothing needs the shared container
        // anymore (the widget direct-fetches, Stop uses Darwin notifications, config is
        // in the bundled plist), so a plain local store is correct and crash-free.
        if let local = try? ModelContainer(for: CaptureEntity.self) {
            container = local
        } else {
            container = try! ModelContainer(
                for: CaptureEntity.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        store = SwiftDataCaptureStore(context: ModelContext(container))

        api = LifeAPIClient(configurationProvider: {
            (LifeAPIBaseURL.normalizedURL(from: KeychainConfig.baseURL), KeychainConfig.token)
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
