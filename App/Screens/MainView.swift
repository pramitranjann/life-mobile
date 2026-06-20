import SwiftUI
import PRLifeKit

struct MainView: View {
    let coordinator: CaptureCoordinator
    let store: SwiftDataCaptureStore
    let api: LifeAPIClient
    @State private var records: [CaptureRecord] = []
    @State private var isRecording = false
    @State private var context: CaptureContext = .quick
    @State private var pendingDelete: CaptureRecord?
    @State private var deletingIDs: Set<UUID> = []
    @State private var deleteError: String?
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
                                            pendingDelete = record
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
            .onAppear {
                refresh()
                AudioRetention(store: store).purge()
                Task {
                    await RetryService(store: store, coordinator: coordinator).sweep()
                    refresh()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { DevicesView() } label: {
                        Text("Devices_").font(Theme.mono(11)).foregroundStyle(Theme.accent)
                    }
                }
            }
            .confirmationDialog("Delete capture?",
                                isPresented: Binding(
                                    get: { pendingDelete != nil },
                                    set: { if !$0 { pendingDelete = nil } }
                                ),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    guard let record = pendingDelete else { return }
                    pendingDelete = nil
                    Task { await delete(record) }
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                if let record = pendingDelete, record.serverEntryId != nil {
                    Text("This will delete the uploaded PR Life entry and remove the local capture.")
                } else {
                    Text("This will remove the local capture from the app.")
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
        } catch {
            deleteError = error.localizedDescription
        }
    }

    private func refresh() { records = store.all() }
}
