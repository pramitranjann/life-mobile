import Foundation

@MainActor
public final class CaptureCoordinator {
    private let store: CaptureStoring
    private let recorder: AudioRecording
    private let transcriber: Transcribing
    private let api: LifeAPIClient
    private let gate: UploadGate

    private var activeID: UUID?

    public init(store: CaptureStoring, recorder: AudioRecording,
                transcriber: Transcribing, api: LifeAPIClient, gate: UploadGate) {
        self.store = store
        self.recorder = recorder
        self.transcriber = transcriber
        self.api = api
        self.gate = gate
    }

    public var isRecording: Bool { activeID != nil }

    public func handle(_ action: PRLifeAction) async {
        switch action {
        case .startCapture(let context): await start(context)
        case .stopCapture: await stop()
        }
    }

    private func start(_ context: CaptureContext) async {
        guard activeID == nil else { return }
        var record = CaptureRecord(context: context, status: .recording)
        activeID = record.id            // reserve synchronously, closes the re-entrancy window
        do {
            let fileName = try await recorder.start()
            record.audioFileName = fileName
            store.insert(record)
        } catch {
            activeID = nil              // release on failure
            record.status = .failed
            record.lastError = "\(error)"
            store.insert(record)
        }
    }

    private func stop() async {
        guard let id = activeID else { return }            // ignore stop when idle
        activeID = nil
        let duration = await recorder.stop()
        store.update(id: id) { $0.duration = duration; $0.status = .processing }

        guard let fileName = store.record(id: id)?.audioFileName else {
            store.update(id: id) { $0.status = .failed; $0.lastError = "missing audio" }
            return
        }

        // Transcribe
        let transcript: String
        do {
            transcript = try await transcriber.transcribe(fileName: fileName)
        } catch {
            store.update(id: id) { $0.status = .failed; $0.lastError = "\(error)" }
            return
        }
        store.update(id: id) { $0.transcript = transcript; $0.status = .uploading }

        // Upload
        await upload(id: id, content: transcript,
                     projectSlug: store.record(id: id)?.context.projectSlug)
    }

    /// Uploads a captured transcript; safe to call again for retry.
    public func upload(id: UUID, content: String, projectSlug: String?) async {
        guard gate.canUploadNow() else {
            store.update(id: id) { $0.status = .failed; $0.lastError = "offline/wifi-gated" }
            return
        }
        do {
            let serverId = try await api.upload(content: content, projectSlug: projectSlug)
            store.update(id: id) { $0.serverEntryId = serverId; $0.status = .done; $0.lastError = nil }
        } catch {
            store.update(id: id) { $0.status = .failed; $0.lastError = "\(error)"; $0.retryCount += 1 }
        }
    }
}
