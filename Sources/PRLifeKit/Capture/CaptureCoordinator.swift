import Foundation

public enum CaptureCoordinatorEvent: Equatable, Sendable {
    /// The recorder has closed the audio file; transcription has not started yet.
    case recordingFinalized(id: UUID, recoveryReason: CaptureRecoveryReason?)
    /// The transcript was durably uploaded.
    case completed(id: UUID)
    /// The capture stopped progressing and is now in the failed state.
    case failed(id: UUID, message: String)
}

@MainActor
public final class CaptureCoordinator {
    private struct FinalizedRecording {
        var duration: TimeInterval
        var inputRoute: AudioInputRoute?
    }

    private let store: CaptureStoring
    private let recorder: AudioRecording
    private let transcriber: Transcribing
    private let api: LifeAPIClient
    private let gate: UploadGate

    private var activeID: UUID?
    private var startInFlight = false
    private var finishRequestedWhileStarting = false
    private var pendingRecoveryReason: CaptureRecoveryReason?
    private var pendingFinalizedRecording: FinalizedRecording?

    /// Optional UI integration point for immediate stop cues and terminal feedback.
    public var eventHandler: ((CaptureCoordinatorEvent) -> Void)?

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

    /// Safely finalizes a partial recording after route loss or an audio interruption.
    /// The existing file continues through transcription/upload and remains available
    /// for retry if either stage fails.
    public func handleRecordingTermination(_ reason: CaptureRecoveryReason) async {
        await finish(recoveryReason: reason, finalizedRecording: nil)
    }

    /// Continues a partial capture that the platform recorder has already closed
    /// and retained. This path deliberately does not call `recorder.stop()` again.
    public func handleFinalizedRecording(
        duration: TimeInterval,
        recoveryReason: CaptureRecoveryReason,
        inputRoute: AudioInputRoute? = nil
    ) async {
        await finish(
            recoveryReason: recoveryReason,
            finalizedRecording: FinalizedRecording(duration: duration, inputRoute: inputRoute)
        )
    }

    /// Retries a failed capture from its furthest durable point. A retained
    /// transcript skips transcription; otherwise the original audio is reused.
    public func retry(id: UUID) async {
        guard let record = store.record(id: id),
              record.status == .failed,
              let fileName = record.audioFileName else { return }

        if let transcript = record.transcript {
            store.update(id: id) { $0.status = .uploading; $0.lastError = nil }
            await upload(id: id, content: transcript, projectSlug: record.context.projectSlug)
            return
        }

        store.update(id: id) { $0.status = .processing; $0.lastError = nil }
        let transcript: String
        do {
            transcript = try await transcriber.transcribe(fileName: fileName)
        } catch {
            let message = "\(error)"
            store.update(id: id) { $0.status = .failed; $0.lastError = message }
            eventHandler?(.failed(id: id, message: message))
            return
        }

        store.update(id: id) { $0.transcript = transcript; $0.status = .uploading }
        await upload(id: id, content: transcript, projectSlug: record.context.projectSlug)
    }

    private func start(_ context: CaptureContext) async {
        guard activeID == nil else { return }
        let record = CaptureRecord(context: context, status: .recording)
        activeID = record.id            // reserve synchronously, closes the re-entrancy window
        startInFlight = true
        store.insert(record)
        do {
            let fileName = try await recorder.start()
            startInFlight = false
            store.update(id: record.id) {
                $0.audioFileName = fileName
                $0.inputRoute = recorder.selectedInputRoute
            }

            if finishRequestedWhileStarting {
                finishRequestedWhileStarting = false
                let recoveryReason = pendingRecoveryReason
                let finalizedRecording = pendingFinalizedRecording
                pendingRecoveryReason = nil
                pendingFinalizedRecording = nil
                await finish(
                    recoveryReason: recoveryReason,
                    finalizedRecording: finalizedRecording
                )
            }
        } catch {
            startInFlight = false
            finishRequestedWhileStarting = false
            pendingRecoveryReason = nil
            pendingFinalizedRecording = nil
            activeID = nil              // release on failure
            let message = "\(error)"
            store.update(id: record.id) { $0.status = .failed; $0.lastError = message }
            eventHandler?(.failed(id: record.id, message: message))
        }
    }

    private func stop() async {
        await finish(recoveryReason: nil, finalizedRecording: nil)
    }

    private func finish(
        recoveryReason: CaptureRecoveryReason?,
        finalizedRecording: FinalizedRecording?
    ) async {
        guard let id = activeID else { return }            // ignore stop when idle
        if startInFlight {
            finishRequestedWhileStarting = true
            if pendingRecoveryReason == nil {
                pendingRecoveryReason = recoveryReason
            }
            if let finalizedRecording {
                pendingFinalizedRecording = finalizedRecording
            }
            return
        }
        activeID = nil
        store.update(id: id) {
            $0.status = .processing
            $0.recoveryReason = recoveryReason
        }
        if let finalizedRecording {
            store.update(id: id) {
                $0.duration = finalizedRecording.duration
                if let inputRoute = finalizedRecording.inputRoute {
                    $0.inputRoute = inputRoute
                }
            }
        } else {
            let duration = await recorder.stop()
            store.update(id: id) { $0.duration = duration }
        }
        eventHandler?(.recordingFinalized(id: id, recoveryReason: recoveryReason))

        guard let fileName = store.record(id: id)?.audioFileName else {
            let message = "missing audio"
            store.update(id: id) { $0.status = .failed; $0.lastError = message }
            eventHandler?(.failed(id: id, message: message))
            return
        }

        // Transcribe
        let transcript: String
        do {
            transcript = try await transcriber.transcribe(fileName: fileName)
        } catch {
            let message = "\(error)"
            store.update(id: id) { $0.status = .failed; $0.lastError = message }
            eventHandler?(.failed(id: id, message: message))
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
            let message = "offline/wifi-gated"
            store.update(id: id) { $0.status = .failed; $0.lastError = message }
            eventHandler?(.failed(id: id, message: message))
            return
        }
        do {
            let serverId = try await api.upload(content: content, projectSlug: projectSlug)
            store.update(id: id) { $0.serverEntryId = serverId; $0.status = .done; $0.lastError = nil }
            eventHandler?(.completed(id: id))
        } catch {
            let message = "\(error)"
            store.update(id: id) { $0.status = .failed; $0.lastError = message; $0.retryCount += 1 }
            eventHandler?(.failed(id: id, message: message))
        }
    }
}
