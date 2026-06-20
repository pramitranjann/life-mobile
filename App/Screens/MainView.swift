import SwiftUI
import PRLifeKit

struct MainView: View {
    let coordinator: CaptureCoordinator
    let store: SwiftDataCaptureStore
    let api: LifeAPIClient
    @State private var records: [CaptureRecord] = []
    @State private var isRecording = false
    @State private var recordingStartedAt: Date?
    @State private var recordingContextName = "Quick"
    @State private var context: CaptureContext = .quick
    @State private var deletingIDs: Set<UUID> = []
    @State private var deleteError: String?
    @State private var showDevices = false
    let activity: LiveActivityController

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("LIFE_").font(Theme.mono(13, .medium)).tracking(1.3).foregroundStyle(Theme.text)
                    Spacer()
                    SyncDot()
                    Text("SYNCED").font(Theme.mono(10)).foregroundStyle(Theme.label)
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.hairline), alignment: .bottom)

                RecordButton(isRecording: isRecording,
                             onPress: { Task { await start() } },
                             onRelease: { Task { await stop() } })
                    .padding(14)

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
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.label)
                    Spacer()
                } else {
                    List {
                        ForEach(records) { record in
                            CaptureRow(record: record,
                                       isDeleting: deletingIDs.contains(record.id))
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    if record.status.isTerminal {
                                        Button(role: .destructive) {
                                            Task { await delete(record) }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        .disabled(deletingIDs.contains(record.id))
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }
                Spacer(minLength: 0)
            }
            .background(Theme.bg.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .navigationDestination(isPresented: $showDevices) { DevicesView() }
            .onReceive(NotificationCenter.default.publisher(for: .openPRLifeSettings)) { _ in
                showDevices = true
            }
            .onAppear {
                refresh()
                AudioRetention(store: store).purge()
                Task {
                    await RetryService(store: store, coordinator: coordinator).sweep()
                    refresh()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: CaptureEnvironment.captureStateDidChange)) { _ in
                refresh()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { DevicesView() } label: {
                        Text("Devices_").font(Theme.mono(11)).foregroundStyle(Theme.accent)
                    }
                }
            }
            .alert("Delete failed",
                   isPresented: Binding(
                    get: { deleteError != nil },
                    set: { if !$0 { deleteError = nil } }
                   )) {
                Button("OK", role: .cancel) { deleteError = nil }
            } message: {
                Text(deleteError ?? "Unknown error")
            }
        }
    }

    private var recordingBanner: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 10, height: 10)
                    Text("RECORDING NOW_")
                        .font(Theme.mono(11, .medium))
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
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.label)
                }
                Text("Capture started from the widget. Tap stop when you're done.")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.label)
            }
            Spacer(minLength: 10)
            Button {
                Task { await stop() }
            } label: {
                Text("STOP_")
                    .font(Theme.mono(11, .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .overlay(Rectangle().stroke(Theme.accent.opacity(0.65), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Theme.accent.opacity(0.07))
        .overlay(Rectangle().stroke(Theme.accent.opacity(0.35), lineWidth: 1))
    }

    private func start() async {
        await coordinator.handle(.startCapture(context: context))
        isRecording = coordinator.isRecording
        if isRecording { activity.start(context: context) }
        refresh()
    }

    private func stop() async {
        guard isRecording else { return }
        await activity.update("SAVING_", phase: .processing, contextName: "Auto-uploading")
        await coordinator.handle(.stopCapture)
        isRecording = coordinator.isRecording   // false after a successful stop
        await activity.end(finalLabel: "RECORDING SAVED_",
                           finalPhase: .saved,
                           finalContextName: "Ready for next capture",
                           dismissAfter: 4)
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
            if let serverEntryId = record.serverEntryId, !serverEntryId.isEmpty {
                try await api.deleteEntry(id: serverEntryId)
            }
            if let audioFileName = record.audioFileName {
                let url = AVAudioRecorderService.capturesDir.appendingPathComponent(audioFileName)
                try? FileManager.default.removeItem(at: url)
            }
            store.remove(id: record.id)
        } catch let LifeAPIError.server(status, _) where status == 404 || status == 405 {
            deleteError = "Your current PR Life API does not support deleting uploaded entries yet. The server only exposes GET/HEAD/OPTIONS/POST for /api/life/entries."
        } catch {
            deleteError = error.localizedDescription
        }
    }

    private func refresh() {
        records = store.all()
        isRecording = coordinator.isRecording
        if let activeRecord = records.first(where: { $0.status == .recording }) {
            recordingStartedAt = activeRecord.createdAt
            recordingContextName = activeRecord.context.displayName
        } else {
            recordingStartedAt = nil
        }
    }
}
