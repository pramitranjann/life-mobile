import Foundation

public enum CaptureWriteDisposition: Equatable, Sendable {
    case uploaded(serverID: String)
    case queued(recordID: UUID)
}

public enum CaptureWriteError: Error, Equatable, LocalizedError {
    case emptyContent
    case durableQueueUnavailable
    case recordNotFound
    case actionNotAllowed

    public var errorDescription: String? {
        switch self {
        case .emptyContent: return "Add some text before saving."
        case .durableQueueUnavailable: return "PR Life could not save a local retry copy."
        case .recordNotFound: return "That capture is no longer available."
        case .actionNotAllowed: return "That action is not available for this capture."
        }
    }
}

public enum CaptureCoordinatorEvent: Equatable, Sendable {
    /// The recorder has closed the audio file; transcription has not started yet.
    case recordingFinalized(id: UUID, recoveryReason: CaptureRecoveryReason?)
    /// The transcript was retained for review instead of auto-uploading.
    case awaitingReview(id: UUID)
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
    private let shouldReviewVoiceCapture: @MainActor () -> Bool

    private var activeID: UUID?
    private var startInFlight = false
    private var finishRequestedWhileStarting = false
    private var pendingRecoveryReason: CaptureRecoveryReason?
    private var pendingFinalizedRecording: FinalizedRecording?

    /// Optional UI integration point for immediate stop cues and terminal feedback.
    public var eventHandler: ((CaptureCoordinatorEvent) -> Void)?

    public init(store: CaptureStoring, recorder: AudioRecording,
                transcriber: Transcribing, api: LifeAPIClient, gate: UploadGate,
                reviewVoiceBeforeUpload: @escaping @MainActor () -> Bool = { false }) {
        self.store = store
        self.recorder = recorder
        self.transcriber = transcriber
        self.api = api
        self.gate = gate
        self.shouldReviewVoiceCapture = reviewVoiceBeforeUpload
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

    /// Retries a failed capture from its furthest durable point. Notes and tasks
    /// use their retained text; voice captures reuse either the transcript or audio.
    public func retry(id: UUID) async {
        guard let record = store.record(id: id),
              record.status == .failed else { return }

        if record.transcript != nil {
            _ = try? await save(id: id)
            return
        }

        guard record.mode == .voice, let fileName = record.audioFileName else { return }

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
        _ = try? await save(id: id)
    }

    /// Creates a durable note record before attempting the network write.
    @discardableResult
    public func createNote(content: String, projectSlug: String?) async throws -> CaptureWriteDisposition {
        try await createTextCapture(
            mode: .note,
            content: content,
            projectSlug: projectSlug,
            dueLocalDate: nil
        )
    }

    /// Creates a durable task record before attempting the network write.
    @discardableResult
    public func createTask(
        title: String,
        projectSlug: String?,
        dueLocalDate: String?
    ) async throws -> CaptureWriteDisposition {
        try await createTextCapture(
            mode: .task,
            content: title,
            projectSlug: projectSlug,
            dueLocalDate: dueLocalDate
        )
    }

    /// Edits a retained transcript/title and project before an explicit save/retry.
    public func updatePending(id: UUID, content: String, projectSlug: String?) throws {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CaptureWriteError.emptyContent }
        guard let record = store.record(id: id) else { throw CaptureWriteError.recordNotFound }
        guard record.status == .reviewing || record.status == .failed else {
            throw CaptureWriteError.actionNotAllowed
        }
        store.update(id: id) {
            $0.transcript = trimmed
            $0.projectSlug = Self.normalizedProject(projectSlug)
            $0.lastError = nil
        }
    }

    /// Saves a reviewed capture or retries a queued write from durable text.
    @discardableResult
    public func save(id: UUID) async throws -> CaptureWriteDisposition {
        guard let record = store.record(id: id) else { throw CaptureWriteError.recordNotFound }
        guard record.status == .reviewing || record.status == .failed || record.status == .uploading else {
            throw CaptureWriteError.actionNotAllowed
        }
        guard let content = record.transcript?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else { throw CaptureWriteError.emptyContent }

        store.update(id: id) { $0.status = .uploading; $0.lastError = nil }
        return await write(id: id, content: content)
    }

    public func discard(id: UUID) throws {
        guard let record = store.record(id: id) else { throw CaptureWriteError.recordNotFound }
        guard record.canDiscard else { throw CaptureWriteError.actionNotAllowed }
        store.remove(id: id)
    }

    private func start(_ context: CaptureContext) async {
        guard activeID == nil else { return }
        let record = CaptureRecord(
            context: context,
            mode: .voice,
            projectSlug: context.projectSlug,
            status: .recording
        )
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
        if shouldReviewVoiceCapture() {
            store.update(id: id) { $0.transcript = transcript; $0.status = .reviewing }
            eventHandler?(.awaitingReview(id: id))
            return
        }
        store.update(id: id) { $0.transcript = transcript; $0.status = .uploading }

        // Upload
        await upload(id: id, content: transcript,
                     projectSlug: store.record(id: id)?.projectSlug)
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

    private func createTextCapture(
        mode: CaptureMode,
        content: String,
        projectSlug: String?,
        dueLocalDate: String?
    ) async throws -> CaptureWriteDisposition {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CaptureWriteError.emptyContent }
        let record = CaptureRecord(
            context: .quick,
            mode: mode,
            projectSlug: Self.normalizedProject(projectSlug),
            taskDueLocalDate: dueLocalDate,
            transcript: trimmed,
            status: .uploading
        )
        store.insert(record)
        guard store.isDurablyStored(id: record.id) else {
            store.remove(id: record.id)
            throw CaptureWriteError.durableQueueUnavailable
        }
        return await write(id: record.id, content: trimmed)
    }

    private func write(id: UUID, content: String) async -> CaptureWriteDisposition {
        guard let record = store.record(id: id) else { return .queued(recordID: id) }
        guard gate.canUploadNow() else {
            let message = "offline/wifi-gated"
            store.update(id: id) { $0.status = .failed; $0.lastError = message }
            eventHandler?(.failed(id: id, message: message))
            return .queued(recordID: id)
        }

        do {
            let serverID: String
            switch record.mode {
            case .voice:
                serverID = try await api.upload(content: content, projectSlug: record.projectSlug)
            case .note:
                let entryID = try await api.createTextEntry(
                    content: content,
                    projectSlug: record.projectSlug
                )
                serverID = "entry:\(entryID)"
            case .task:
                let task = try await api.createTask(TaskPayload(
                    title: content,
                    projectSlug: record.projectSlug,
                    dueLocalDate: record.taskDueLocalDate
                ))
                serverID = "task:\(task.id)"
            }
            store.update(id: id) {
                $0.serverEntryId = serverID
                $0.status = .done
                $0.lastError = nil
            }
            eventHandler?(.completed(id: id))
            return .uploaded(serverID: serverID)
        } catch {
            let message = error.localizedDescription
            store.update(id: id) {
                $0.status = .failed
                $0.lastError = message
                $0.retryCount += 1
            }
            eventHandler?(.failed(id: id, message: message))
            return .queued(recordID: id)
        }
    }

    private static func normalizedProject(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
