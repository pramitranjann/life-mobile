import Foundation
import Combine
import SwiftData
import UIKit
import WidgetKit
import PRLifeKit

extension Notification.Name {
    static let openPRLifeSettings = Notification.Name("openPRLifeSettings")
    static let openPRLifeNote = Notification.Name("openPRLifeNote")
}

/// Process-wide capture stack, built once from persistent config. Used by both the
/// UI and App Intents so every entry point shares one coordinator/store/activity.
@MainActor
final class CaptureEnvironment: ObservableObject {
    static let shared = CaptureEnvironment()
    static let captureStateDidChange = Notification.Name("CaptureEnvironment.captureStateDidChange")

    let container: ModelContainer
    let store: SwiftDataCaptureStore
    let recorder: AVAudioRecorderService
    let coordinator: CaptureCoordinator
    let api: LifeAPIClient
    let activity = LiveActivityController()
    private let cuePlayer = CaptureCuePlayer()
    @Published private(set) var syncState = LifeSyncState()
    @Published private(set) var audioInputs: [AudioInputDescriptor] = []
    @Published private(set) var selectedAudioInput: AudioInputDescriptor?
    @Published private(set) var audioInputError: String?

    private var cueTail: Task<Void, Never>?
    private var captureStartPending = false
    private var stopRequestedDuringStartCue = false

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
        recorder = AVAudioRecorderService()
        coordinator = CaptureCoordinator(store: store, recorder: recorder,
                                         transcriber: SpeechTranscriber(), api: api, gate: gate,
                                         reviewVoiceBeforeUpload: {
                                             UserDefaults.standard.bool(forKey: "reviewVoiceBeforeUpload")
                                         })
        UserDefaults.standard.register(defaults: [
            "backgroundRecording": true,
            "reviewVoiceBeforeUpload": false,
        ])

        recorder.onEvent = { [weak self] event in
            Task { @MainActor in await self?.handleRecorderEvent(event) }
        }
        coordinator.eventHandler = { [weak self] event in
            Task { @MainActor in self?.handleCoordinatorEvent(event) }
        }

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
        case "note":
            NotificationCenter.default.post(name: .openPRLifeNote, object: nil)
        case "event":
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "id" })?.value
            await openWebPath(LifeWebRoute.calendar(eventID: id).path)
        case "task":
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "id" })?.value
            await openWebPath(LifeWebRoute.tasks(taskID: id).path)
        case "web":
            if let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "path" })?.value {
                await openWebPath(path)
            }
        default:
            return
        }
    }

    private func openWebPath(_ path: String) async {
        guard path.hasPrefix("/life/"),
              let baseURL = LifeAPIBaseURL.normalizedURL(from: KeychainConfig.baseURL),
              let destination = URL(string: path, relativeTo: baseURL)?.absoluteURL else { return }
        await UIApplication.shared.open(destination)
    }

    func startCapture(context: CaptureContext) async {
        guard !coordinator.isRecording, !captureStartPending else { return }
        captureStartPending = true
        stopRequestedDuringStartCue = false
        await enqueueCue(.start).value
        captureStartPending = false
        if stopRequestedDuringStartCue {
            stopRequestedDuringStartCue = false
            return
        }
        await coordinator.handle(.startCapture(context: context))
        if coordinator.isRecording {
            activity.start(context: context)
        }
        updatePendingCaptureCount()
        publishCaptureStateChange()
    }

    func stopCaptureFromAnySurface() async {
        if captureStartPending {
            stopRequestedDuringStartCue = true
            return
        }
        guard coordinator.isRecording else { return }
        let activeID = store.all().first(where: { $0.status == .recording })?.id
        syncState = syncState.beginningSync()
        await activity.update("SAVING_", phase: .processing, contextName: "Auto-uploading")
        await coordinator.handle(.stopCapture)
        await completeCaptureFlow(activeID: activeID)
    }

    func refreshAudioInputs() async {
        do {
            audioInputs = try await recorder.prepareInputSelection()
            selectedAudioInput = recorder.currentInput
                ?? audioInputs.first(where: { $0.id == selectedAudioInput?.id })
                ?? audioInputs.first
            audioInputError = nil
        } catch {
            audioInputError = error.localizedDescription
        }
    }

    func selectAudioInput(id: String?) async {
        do {
            if audioInputs.isEmpty {
                audioInputs = try await recorder.prepareInputSelection()
            }
            try recorder.selectInput(id: id)
            selectedAudioInput = id.flatMap { selectedID in
                audioInputs.first(where: { $0.id == selectedID })
            } ?? recorder.currentInput ?? audioInputs.first
            audioInputError = nil
        } catch {
            audioInputError = error.localizedDescription
            await refreshAudioInputs()
        }
    }

    func resumeCapture(_ record: CaptureRecord) async {
        await startCapture(context: record.context)
    }

    func retryCapture(_ record: CaptureRecord) async {
        guard record.canRetry else { return }
        syncState = syncState.beginningSync()
        await coordinator.retry(id: record.id)
        updatePendingCaptureCount()
        if let refreshed = store.record(id: record.id) {
            if refreshed.status == .done {
                recordAPIResult(.authenticated)
            } else {
                recordAPIResult(.failed(refreshed.lastError ?? "Retry failed."))
            }
        }
        publishCaptureStateChange()
    }

    func createNote(content: String, context: CaptureContext) async -> String? {
        await performTextWrite {
            try await coordinator.createNote(content: content, projectSlug: context.projectSlug)
        }
    }

    func createTask(title: String, context: CaptureContext, dueDate: Date?) async -> String? {
        await performTextWrite {
            try await coordinator.createTask(
                title: title,
                projectSlug: context.projectSlug,
                dueLocalDate: dueDate.map(Self.localDateString)
            )
        }
    }

    func savePendingCapture(_ record: CaptureRecord, content: String, context: CaptureContext) async -> String? {
        do {
            try coordinator.updatePending(
                id: record.id,
                content: content,
                projectSlug: context.projectSlug
            )
            store.update(id: record.id) { $0.context = context }
            syncState = syncState.beginningSync()
            let disposition = try await coordinator.save(id: record.id)
            applyWriteDisposition(disposition)
            publishCaptureStateChange()
            return nil
        } catch {
            recordAPIFailure(error)
            publishCaptureStateChange()
            return error.localizedDescription
        }
    }

    func discardCapture(_ record: CaptureRecord) -> String? {
        do {
            if let audioFileName = record.audioFileName {
                let url = AVAudioRecorderService.capturesDir.appendingPathComponent(audioFileName)
                try? FileManager.default.removeItem(at: url)
            }
            try coordinator.discard(id: record.id)
            updatePendingCaptureCount()
            publishCaptureStateChange()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func performTextWrite(
        _ operation: () async throws -> CaptureWriteDisposition
    ) async -> String? {
        syncState = syncState.beginningSync()
        do {
            let disposition = try await operation()
            applyWriteDisposition(disposition)
            updatePendingCaptureCount()
            publishCaptureStateChange()
            return nil
        } catch {
            recordAPIFailure(error)
            updatePendingCaptureCount()
            publishCaptureStateChange()
            return error.localizedDescription
        }
    }

    private func applyWriteDisposition(_ disposition: CaptureWriteDisposition) {
        switch disposition {
        case .uploaded:
            recordAPIResult(.authenticated)
        case .queued:
            recordAPIResult(.failed("Saved locally and queued for retry."))
        }
    }

    private static func localDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func completeCaptureFlow(activeID: UUID?) async {
        let record = activeID.flatMap(store.record(id:))
        let succeeded = record?.status == .done
        let awaitingReview = record?.status == .reviewing
        let retained = record?.audioFileName != nil
        await activity.end(
            finalLabel: succeeded
                ? "RECORDING SAVED_"
                : (awaitingReview ? "REVIEW CAPTURE_" : (retained ? "RECORDING KEPT_" : "CAPTURE FAILED_")),
            finalPhase: succeeded ? .saved : .processing,
            finalContextName: succeeded
                ? "Ready for next capture"
                : (awaitingReview ? "Transcript ready to review" : "Open PR Life to retry"),
            dismissAfter: 4
        )
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
            case .reviewing:
                recordAPIResult(await api.probeAuthenticatedConnectivity())
            case .recording, .processing, .uploading:
                break
            }
        } else {
            recordAPIResult(.failed("No active capture was available to sync."))
        }
        publishCaptureStateChange()
    }

    private func handleRecorderEvent(_ event: AudioRecorderEvent) async {
        switch event {
        case .routeChanged(_, let currentInput, let availableInputs):
            audioInputs = availableInputs
            selectedAudioInput = currentInput
            audioInputError = nil
        case .recordingStopped(let retained):
            guard retained.reason != .requested else { return }
            let recoveryReason: CaptureRecoveryReason = retained.reason == .routeUnavailable
                ? .inputRouteLost
                : .audioInterrupted
            syncState = syncState.beginningSync()
            await activity.update("AUDIO SAVED_", phase: .processing, contextName: "Recovering partial capture")
            let route = retained.input.map {
                AudioInputRoute(identifier: $0.id, name: $0.name, portType: $0.portType)
            }
            let activeID = store.all().first(where: { $0.status == .recording })?.id
            await coordinator.handleFinalizedRecording(
                duration: retained.duration,
                recoveryReason: recoveryReason,
                inputRoute: route
            )
            await completeCaptureFlow(activeID: activeID)
        case .enteredBackground:
            guard coordinator.isRecording,
                  !UserDefaults.standard.bool(forKey: "backgroundRecording") else { return }
            let activeID = store.all().first(where: { $0.status == .recording })?.id
            await coordinator.handleRecordingTermination(.audioInterrupted)
            await completeCaptureFlow(activeID: activeID)
        case .interruptionBegan, .interruptionEnded, .enteredForeground, .mediaServicesReset:
            break
        }
    }

    private func handleCoordinatorEvent(_ event: CaptureCoordinatorEvent) {
        switch event {
        case .recordingFinalized:
            enqueueCue(.stop)
        case .awaitingReview:
            enqueueCue(.saved)
        case .completed:
            enqueueCue(.saved)
        case .failed:
            enqueueCue(.failure)
        }
        updatePendingCaptureCount()
        publishCaptureStateChange()
    }

    @discardableResult
    private func enqueueCue(_ cue: CaptureCue) -> Task<Void, Never> {
        let previous = cueTail
        let player = cuePlayer
        let task = Task { @MainActor in
            await previous?.value
            await player.play(cue)
        }
        cueTail = task
        return task
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
        LifeWidgetTimelineReloader.reloadUpcoming()
    }
}
