import SwiftUI
import PRLifeKit

struct MainView: View {
    @ObservedObject private var environment = CaptureEnvironment.shared
    let coordinator: CaptureCoordinator
    let store: SwiftDataCaptureStore
    let api: LifeAPIClient
    let notificationPresenter: UserNotificationPresenter
    @State private var records: [CaptureRecord] = []
    @State private var isRecording = false
    @State private var recordingStartedAt: Date?
    @State private var recordingContextName = "Quick"
    @State private var context: CaptureContext = .quick
    @State private var captureMode: MobileCaptureMode = .voice
    @State private var textCaptureContent = ""
    @State private var taskDueDate: Date?
    @State private var isSavingTextCapture = false
    @State private var textCaptureError: String?
    @State private var editingRecord: CaptureRecord?
    @State private var isSavingEditedCapture = false
    @State private var editedCaptureError: String?
    @State private var deletingIDs: Set<UUID> = []
    @State private var deleteError: String?
    @State private var showDevices = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("LIFE_").font(Theme.mono(14, .medium)).tracking(2).foregroundStyle(Theme.text)
                    Spacer()
                    SyncDot(connected: environment.syncState.status == .synced)
                    Text(syncSummary)
                        .font(Theme.mono(11))
                        .foregroundStyle(syncColor)
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.hairline), alignment: .bottom)

                CaptureModePicker(selection: $captureMode)
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .disabled(isRecording)

                if captureMode == .voice {
                    RecordButton(isRecording: isRecording,
                                 onPress: { Task { await start() } },
                                 onRelease: { Task { await stop() } })
                        .padding(14)

                    audioInputBar
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                } else {
                    TextCaptureComposer(
                        mode: captureMode,
                        content: $textCaptureContent,
                        context: $context,
                        dueDate: $taskDueDate,
                        isSaving: isSavingTextCapture,
                        errorMessage: textCaptureError,
                        onSave: { Task { await saveTextCapture() } }
                    )
                    .padding(14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if isRecording {
                    recordingBanner
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }

                SectionLabel(text: "CAPTURES_", trailing: "\(records.count) total")
                    .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 10)

                if records.isEmpty {
                    Spacer()
                    Text("No captures yet")
                        .font(Theme.mono(13))
                        .foregroundStyle(Theme.label)
                    Spacer()
                } else {
                    List {
                        ForEach(records) { record in
                            captureListRow(record)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }
                Spacer(minLength: 0)
            }
            .animation(.easeOut(duration: 0.2), value: captureMode)
            .background(Theme.bg.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .navigationDestination(isPresented: $showDevices) {
                DevicesView(notificationPresenter: notificationPresenter)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openPRLifeSettings)) { _ in
                showDevices = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .openPRLifeNote)) { _ in
                captureMode = .note
            }
            .onAppear {
                refresh()
                AudioRetention(store: store).purge()
                Task {
                    await environment.refreshAudioInputs()
                    await RetryService(store: store, coordinator: coordinator).sweep()
                    refresh()
                    await environment.refreshAPIConnectivity()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: CaptureEnvironment.captureStateDidChange)) { _ in
                refresh()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { DevicesView(notificationPresenter: notificationPresenter) } label: {
                        // The screen is settings (API, recording, notifications,
                        // diagnostics) — only two rows are devices.
                        Text("Settings_").font(Theme.mono(12)).foregroundStyle(Theme.accent)
                    }
                }
            }
            .alert("Action failed",
                   isPresented: Binding(
                    get: { deleteError != nil },
                    set: { if !$0 { deleteError = nil } }
                   )) {
                Button("OK", role: .cancel) { deleteError = nil }
            } message: {
                Text(deleteError ?? "Unknown error")
            }
            .sheet(item: $editingRecord) { record in
                PendingCaptureEditor(
                    record: record,
                    isSaving: isSavingEditedCapture,
                    errorMessage: editedCaptureError,
                    onSave: { content, context in
                        Task { await saveEditedCapture(record, content: content, context: context) }
                    },
                    onRetry: {
                        Task {
                            await environment.retryCapture(record)
                            refresh()
                            if store.record(id: record.id)?.status == .done {
                                editingRecord = nil
                            }
                        }
                    },
                    onDiscard: {
                        editedCaptureError = environment.discardCapture(record)
                        if editedCaptureError == nil {
                            editingRecord = nil
                            refresh()
                        }
                    }
                )
            }
        }
    }

    private func captureListRow(_ record: CaptureRecord) -> some View {
        let onResume: (() -> Void)? = record.canResume ? {
            Task { await environment.resumeCapture(record) }
        } : nil
        let onRetry: (() -> Void)? = record.canRetry ? {
            Task { await environment.retryCapture(record) }
        } : nil
        let isRecoverable = record.status == .reviewing || record.status == .failed

        return CaptureRow(
            record: record,
            isDeleting: deletingIDs.contains(record.id),
            onEdit: record.canSave ? {
                editedCaptureError = nil
                editingRecord = record
            } : nil,
            onResume: onResume,
            onRetry: onRetry,
            onDiscard: isRecoverable ? {
                deleteError = environment.discardCapture(record)
                refresh()
            } : nil
        )
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            deleteSwipeAction(for: record)
        }
    }

    @ViewBuilder
    private func deleteSwipeAction(for record: CaptureRecord) -> some View {
        if record.status.isTerminal {
            Button(role: .destructive) {
                Task { await delete(record) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(deletingIDs.contains(record.id))
        }
    }

    private var audioInputBar: some View {
        HStack(spacing: 10) {
            Image(systemName: environment.selectedAudioInput?.portType.contains("Bluetooth") == true
                  ? "airpodspro" : "mic.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 24, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text("AUDIO INPUT_")
                    .font(Theme.mono(10, .medium))
                    .foregroundStyle(Theme.label)
                Text((environment.audioInputError
                      ?? environment.selectedAudioInput?.name
                      ?? "Checking microphones").uppercased())
                    .font(Theme.mono(12, .medium))
                    .foregroundStyle(environment.audioInputError == nil ? Theme.text : Theme.danger)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let input = environment.selectedAudioInput,
               input.supportsHighQualityBluetoothRecording {
                Text(input.isHighQualityBluetoothRecordingEnabled ? "HQ ON_" : "HQ READY_")
                    .font(Theme.mono(10, .medium))
                    .foregroundStyle(input.isHighQualityBluetoothRecordingEnabled ? Theme.green : Theme.amber)
            }

            if environment.audioInputs.count > 1 {
                Menu {
                    ForEach(environment.audioInputs) { input in
                        Button {
                            Task { await environment.selectAudioInput(id: input.id) }
                        } label: {
                            if input.id == environment.selectedAudioInput?.id {
                                Label(input.name, systemImage: "checkmark")
                            } else {
                                Text(input.name)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(isRecording)
                .accessibilityLabel("Choose audio input")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, environment.audioInputs.count > 1 ? 2 : 12)
        .frame(minHeight: 48)
        .background(Theme.mutedBG)
        .overlay(Rectangle().stroke(Theme.border, lineWidth: 1))
        .animation(.easeOut(duration: 0.16), value: environment.selectedAudioInput?.id)
    }

    private var recordingBanner: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 10, height: 10)
                    Text("RECORDING NOW_")
                        .font(Theme.mono(12, .medium))
                        .foregroundStyle(Theme.accent)
                }
                HStack(spacing: 8) {
                    if let recordingStartedAt {
                        Text(recordingStartedAt, style: .timer)
                            .monospacedDigit()
                            .font(Theme.mono(18, .medium))
                            .foregroundStyle(Theme.text)
                    }
                    Text(recordingContextName.uppercased())
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.label)
                }
                Text("Capture is active. Tap stop when you're done.")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.label)
            }
            Spacer(minLength: 10)
            Button {
                Task { await stop() }
            } label: {
                Text("STOP_")
                    .font(Theme.mono(13, .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .overlay(Rectangle().stroke(Theme.accent, lineWidth: 1))
            }
            .buttonStyle(.pressable)
        }
        .padding(14)
        .background(Theme.accentSoft)
        .overlay(Rectangle().stroke(Theme.accentLine, lineWidth: 1))
    }

    private func start() async {
        await environment.startCapture(context: context)
        isRecording = coordinator.isRecording
        refresh()
    }

    private func stop() async {
        await environment.stopCaptureFromAnySurface()
        isRecording = coordinator.isRecording   // false after a successful stop
        refresh()
    }

    private func saveTextCapture() async {
        guard captureMode != .voice else { return }
        isSavingTextCapture = true
        defer { isSavingTextCapture = false }

        switch captureMode {
        case .voice:
            return
        case .note:
            textCaptureError = await environment.createNote(
                content: textCaptureContent,
                context: context
            )
        case .task:
            textCaptureError = await environment.createTask(
                title: textCaptureContent,
                context: context,
                dueDate: taskDueDate
            )
        }

        if textCaptureError == nil {
            textCaptureContent = ""
            taskDueDate = nil
        }
        refresh()
    }

    private func saveEditedCapture(
        _ record: CaptureRecord,
        content: String,
        context: CaptureContext
    ) async {
        isSavingEditedCapture = true
        defer { isSavingEditedCapture = false }
        editedCaptureError = await environment.savePendingCapture(
            record,
            content: content,
            context: context
        )
        if editedCaptureError == nil {
            editingRecord = nil
        }
        refresh()
    }

    @MainActor
    private func delete(_ record: CaptureRecord) async {
        guard !deletingIDs.contains(record.id) else { return }
        deletingIDs.insert(record.id)
        defer {
            deletingIDs.remove(record.id)
            refresh()
        }

        do {
            if let serverEntryId = deletableServerEntryID(for: record) {
                environment.beginAPIOperation()
                try await api.deleteEntry(id: serverEntryId)
                environment.recordAPIResult(.authenticated)
            }
            if let audioFileName = record.audioFileName {
                let url = AVAudioRecorderService.capturesDir.appendingPathComponent(audioFileName)
                try? FileManager.default.removeItem(at: url)
            }
            store.remove(id: record.id)
        } catch let LifeAPIError.server(status, _) where status == 404 || status == 405 {
            environment.recordAPIResult(.failed("The API does not support deleting this entry."))
            deleteError = "Your current PR Life API does not support deleting uploaded entries yet. The server only exposes GET/HEAD/OPTIONS/POST for /api/life/entries."
        } catch {
            environment.recordAPIFailure(error)
            deleteError = error.localizedDescription
        }
    }

    private func deletableServerEntryID(for record: CaptureRecord) -> String? {
        guard let serverID = record.serverEntryId, !serverID.isEmpty else { return nil }
        if serverID.hasPrefix("task:") { return nil }
        if serverID.hasPrefix("entry:") { return String(serverID.dropFirst("entry:".count)) }
        return serverID
    }

    private func refresh() {
        records = store.all()
        environment.updatePendingCaptureCount()
        isRecording = coordinator.isRecording
        if let activeRecord = records.first(where: { $0.status == .recording }) {
            recordingStartedAt = activeRecord.createdAt
            recordingContextName = activeRecord.context.displayName
        } else {
            recordingStartedAt = nil
        }
    }

    private var syncSummary: String {
        let status: String
        switch environment.syncState.status {
        case .idle: status = "NOT CHECKED_"
        case .syncing: status = "SYNCING_"
        case .synced: status = "SYNCED_"
        case .offline: status = "OFFLINE_"
        case .notConfigured: status = "NOT CONFIGURED_"
        case .authenticationFailed: status = "AUTH FAILED_"
        case .failed: status = "SYNC FAILED_"
        }

        let pending = environment.syncState.pendingCaptureCount
        return pending > 0 ? "\(status) · \(pending) PENDING" : status
    }

    private var syncColor: Color {
        switch environment.syncState.status {
        case .synced: environment.syncState.pendingCaptureCount > 0 ? Theme.amber : Theme.green
        case .syncing: Theme.accent
        case .offline, .notConfigured, .idle: Theme.label
        case .authenticationFailed, .failed: Theme.danger
        }
    }
}
