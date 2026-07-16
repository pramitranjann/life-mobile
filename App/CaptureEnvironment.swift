import Foundation
import Combine
import SwiftData
import WidgetKit
import PRLifeKit

extension Notification.Name {
    static let openPRLifeSettings = Notification.Name("openPRLifeSettings")
}

/// Process-wide capture stack, built once from persistent config. Used by both the
/// UI and App Intents so every entry point shares one coordinator/store/activity.
@MainActor
final class CaptureEnvironment: ObservableObject {
    static let shared = CaptureEnvironment()
    static let captureStateDidChange = Notification.Name("CaptureEnvironment.captureStateDidChange")

    let container: ModelContainer
    let store: SwiftDataCaptureStore
    let coordinator: CaptureCoordinator
    let api: LifeAPIClient
    let activity = LiveActivityController()
    @Published private(set) var syncState = LifeSyncState()

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
            await self.startCapture(context: ctx)
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
            await startCapture(context: context)
        case "stop":
            await stopCaptureFromAnySurface()
        case "settings":
            NotificationCenter.default.post(name: .openPRLifeSettings, object: nil)
        default:
            return
        }
    }

    func startCapture(context: CaptureContext) async {
        await coordinator.handle(.startCapture(context: context))
        if coordinator.isRecording {
            activity.start(context: context)
        }
        updatePendingCaptureCount()
        publishCaptureStateChange()
    }

    func stopCaptureFromAnySurface() async {
        let activeID = store.all().first(where: { $0.status == .recording })?.id
        syncState = syncState.beginningSync()
        await activity.update("SAVING_", phase: .processing, contextName: "Auto-uploading")
        await coordinator.handle(.stopCapture)
        await activity.end(finalLabel: "RECORDING SAVED_",
                           finalPhase: .saved,
                           finalContextName: "Ready for next capture",
                           dismissAfter: 4)
        updatePendingCaptureCount()

        if let activeID, let record = store.record(id: activeID) {
            switch record.status {
            case .done:
                recordAPIResult(.authenticated)
            case .failed:
                if record.transcript == nil {
                    recordAPIResult(.failed(record.lastError ?? "Capture failed before it could sync."))
                } else if record.lastError == "offline/wifi-gated" {
                    recordAPIResult(.failed("Upload is waiting for an allowed network connection."))
                } else {
                    let connectivity = await api.probeAuthenticatedConnectivity()
                    if connectivity == .authenticated {
                        recordAPIResult(.failed(record.lastError ?? "The capture could not be uploaded."))
                    } else {
                        recordAPIResult(connectivity)
                    }
                }
            case .recording, .processing, .uploading:
                break
            }
        } else {
            recordAPIResult(.failed("No active capture was available to sync."))
        }
        publishCaptureStateChange()
    }

    /// Runs a real authenticated request. Cached data and reachability alone never
    /// transition the UI to `synced`.
    @discardableResult
    func refreshAPIConnectivity() async -> LifeAPIConnectivity {
        syncState = syncState.beginningSync()
        let result = await api.probeAuthenticatedConnectivity()
        recordAPIResult(result)
        publishCaptureStateChange()
        return result
    }

    func beginAPIOperation() {
        syncState = syncState.beginningSync()
    }

    func recordAPIResult(_ result: LifeAPIConnectivity) {
        syncState = syncState.applying(result)
    }

    func recordAPIFailure(_ error: Error) {
        recordAPIResult(LifeAPIConnectivity.classify(error: error))
    }

    func updatePendingCaptureCount() {
        let pendingCount = store.all().filter { $0.status != .done }.count
        syncState = syncState.updatingPendingCaptureCount(pendingCount)
    }

    private func publishCaptureStateChange() {
        NotificationCenter.default.post(name: Self.captureStateDidChange, object: nil)
        WidgetCenter.shared.reloadTimelines(ofKind: "PRLifeUpcoming")
    }
}
