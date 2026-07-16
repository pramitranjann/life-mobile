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
            (LifeAPIBaseURL.normalizedURL(from: KeychainConfig.baseURL), KeychainConfig.token)
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

    /// Registers the global chords. Toggle semantics: a hotkey starts a capture, and ANY
    /// hotkey pressed while recording stops the current capture (it does not re-target to a
    /// new context). Switching context means stop, then start again.
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

    @discardableResult
    func createQuickNote(_ content: String) async throws -> CaptureRecord {
        let entryId = try await api.createTextEntry(content: content, projectSlug: nil)
        let record = CaptureRecord(
            context: .quick,
            transcript: content,
            status: .done,
            serverEntryId: "entry:\(entryId)"
        )
        store.insert(record)
        objectWillChange.send()
        return record
    }

    @discardableResult
    func createQuickTask(_ title: String) async throws -> CaptureRecord {
        let task = try await api.createTask(TaskPayload(title: title))
        let record = CaptureRecord(
            context: .quick,
            transcript: title,
            status: .done,
            serverEntryId: "task:\(task.id)"
        )
        store.insert(record)
        objectWillChange.send()
        return record
    }

    func updateTextCapture(id: UUID, content: String) async throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let record = store.record(id: id) else { return }

        if let serverID = record.serverEntryId {
            if serverID.hasPrefix("task:") {
                try await api.updateTask(id: String(serverID.dropFirst("task:".count)), title: trimmed)
            } else {
                let entryID = serverID.hasPrefix("entry:") ? String(serverID.dropFirst("entry:".count)) : serverID
                try await api.updateTextEntry(id: entryID, content: trimmed)
            }
        }

        store.update(id: id) { $0.transcript = trimmed; $0.lastError = nil }
        objectWillChange.send()
    }
}
