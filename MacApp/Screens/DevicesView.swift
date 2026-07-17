import SwiftUI
import PRLifeKit

/// Devices tab (Screen 6): live keyboard shortcuts, future-hardware rows, architecture note.
struct DevicesView: View {
    @ObservedObject var sync: LifeSyncService

    /// Derived from the kit's single source of truth so the tiles never drift from the
    /// chords actually registered by CarbonHotKeyManager.
    private var shortcuts: [(String, String)] {
        HotKeyBinding.defaults.map { ($0.context.displayName, Self.chordGlyph(for: $0.context)) }
    }

    private static func chordGlyph(for context: CaptureContext) -> String {
        switch context {
        case .quick: return "⌃⌥⎵"
        case .work: return "⌃⌥W"
        case .journal: return "⌃⌥J"
        case .ideas: return "⌃⌥I"
        }
    }
    private let hardware: [(String, String)] = [
        ("Desk Dock", "4 buttons · mic · LED · NFC"),
        ("NFC Tags", "Context triggers · tap to capture"),
        ("Bluetooth · USB", "Pebble · Stream Deck · custom"),
    ]
    private let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                apiSection
                shortcutsSection
                hardwareSection
                architectureNote
            }
            .padding(20)
        }
    }

    private var apiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "PR LIFE API_")
            HStack {
                switch sync.state {
                case .synced: SyncDot(color: Theme.green, text: "Connected")
                case .syncing: SyncDot(color: Theme.amber, text: "Syncing…")
                case .failed: SyncDot(color: Theme.danger, text: "Disconnected")
                case .idle: SyncDot(color: Theme.label, text: "Not synced")
                }
                Spacer()
                Button { Task { await sync.refresh() } } label: {
                    Text("Sync →").font(Theme.mono(11)).foregroundStyle(Theme.accent)
                }.buttonStyle(.pressable)
            }
            .padding(12)
            .background(Theme.panel)
            .overlay(Rectangle().stroke(Theme.border, lineWidth: 1))
        }
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "KEYBOARD SHORTCUTS_")
                Spacer()
                SyncDot(color: Theme.green, text: "ACTIVE")
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(shortcuts, id: \.0) { label, chord in
                    HStack {
                        Text(label).font(Theme.body(12)).foregroundStyle(Theme.muted)
                        Spacer()
                        Text(chord).font(Theme.mono(11, .medium)).foregroundStyle(Theme.text)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.mutedBG)
                    .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
                }
            }
        }
    }

    private var hardwareSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "HARDWARE_")
            ForEach(hardware, id: \.0) { name, specs in
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(name).font(Theme.body(13)).foregroundStyle(Theme.label)
                        Text(specs).font(Theme.mono(10)).foregroundStyle(Theme.label)
                    }
                    Spacer()
                    Text("Coming soon_")
                        .font(Theme.mono(10)).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Theme.mutedBG)
                .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
            }
        }
    }

    private var architectureNote: some View {
        Text("All input sources — physical buttons, keyboard shortcuts, NFC tags, Bluetooth — map to the same internal action system.")
            .font(Theme.mono(11))
            .lineSpacing(5)
            .foregroundStyle(Theme.label)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.mutedBG)
            .overlay(Rectangle().fill(Theme.border).frame(width: 2), alignment: .leading)
    }
}
