import PRLifeKit
import SwiftUI

@MainActor
struct NotificationInboxView: View {
    let api: LifeAPIClient

    @Environment(\.openURL) private var openURL
    @State private var notifications: [LifeNotification] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var updatingIDs = Set<String>()

    var body: some View {
        Group {
            if isLoading && notifications.isEmpty {
                ProgressView()
                    .tint(Theme.accent)
            } else if notifications.isEmpty {
                VStack(spacing: 8) {
                    Text("NO ALERTS_")
                        .font(Theme.mono(12, .medium))
                        .foregroundStyle(Theme.text)
                    Text(errorMessage ?? "Server notification history will appear here.")
                        .font(Theme.mono(11))
                        .foregroundStyle(errorMessage == nil ? Theme.label : Theme.danger)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            } else {
                List(notifications) { notification in
                    row(notification)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await load() }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .navigationTitle("ALERT INBOX_")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .safeAreaInset(edge: .bottom) {
            if let errorMessage, !notifications.isEmpty {
                Text(errorMessage)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(Theme.panel)
            }
        }
    }

    private func row(_ notification: LifeNotification) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(notification.readAt == nil ? Theme.accent : Theme.border)
                    .frame(width: 6, height: 6)
                Text(notification.title)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                Text(notification.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.label)
            }

            Text(notification.body)
                .font(Theme.body(13))
                .foregroundStyle(Theme.muted)

            HStack(spacing: 16) {
                if notification.readAt == nil {
                    Button("MARK READ_") {
                        Task { await setRead(notification, read: true) }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .disabled(updatingIDs.contains(notification.id))
                } else {
                    Button("MARK UNREAD_") {
                        Task { await setRead(notification, read: false) }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .disabled(updatingIDs.contains(notification.id))
                }

                if let destination = notification.url {
                    Button("OPEN SOURCE_") {
                        Task {
                            if notification.readAt == nil {
                                await setRead(notification, read: true)
                            }
                            openURL(destination)
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
            }
            .font(Theme.mono(12, .medium))
            .foregroundStyle(Theme.accent)
            .buttonStyle(.pressable)
        }
        .padding(14)
        .background(notification.readAt == nil ? Theme.panel : Theme.mutedBG)
        .overlay(Rectangle().stroke(Theme.border, lineWidth: 1))
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            notifications = try await api.fetchNotifications(after: nil, limit: 100)
                .sorted {
                    if $0.createdAt == $1.createdAt { return $0.id > $1.id }
                    return $0.createdAt > $1.createdAt
                }
            errorMessage = nil
        } catch {
            errorMessage = "Could not load alerts: \(error.localizedDescription)"
        }
    }

    private func setRead(_ notification: LifeNotification, read: Bool) async {
        guard updatingIDs.insert(notification.id).inserted else { return }
        defer { updatingIDs.remove(notification.id) }
        do {
            let updated = try await api.setNotificationRead(id: notification.id, read: read)
            guard let index = notifications.firstIndex(where: { $0.id == updated.id }) else { return }
            notifications[index] = updated
            errorMessage = nil
        } catch {
            errorMessage = "Could not update alert: \(error.localizedDescription)"
        }
    }
}
