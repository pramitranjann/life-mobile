import SwiftUI
import PRLifeKit

enum MainTab: String, CaseIterable {
    case today = "Today_"
    case captures = "Captures_"
    case devices = "Devices_"
}

/// The main dashboard window (CODEX_PROMPT Screens 5–6): a nav-tab bar over the
/// Today / Captures / Devices content.
struct MainWindow: View {
    @ObservedObject var env: MacCaptureEnvironment
    @ObservedObject var sync: LifeSyncService
    @State private var tab: MainTab = .today

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            navTabs
            Group {
                switch tab {
                case .today: TodayView(sync: sync)
                case .captures: CapturesView(env: env, sync: sync)
                case .devices: DevicesView(sync: sync)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 520, idealWidth: 900, minHeight: 480, idealHeight: 600)
        .background(Theme.bg)
        .onExitCommand { if env.isRecording { env.stopCapture() } }   // Esc stops an active capture
    }

    private var titleBar: some View {
        ZStack {
            Text("PR LIFE_").font(Theme.mono(12)).tracking(1.0).foregroundStyle(Theme.label)
        }
        .frame(maxWidth: .infinity).frame(height: 40)
        .background(Theme.panel)
        .overlay(Rectangle().fill(Theme.hairline).frame(height: 1), alignment: .bottom)
    }

    private var navTabs: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { item in
                Button { tab = item } label: {
                    VStack(spacing: 0) {
                        Text(item.rawValue)
                            .font(Theme.mono(10, tab == item ? .medium : .regular))
                            .foregroundStyle(tab == item ? Theme.accent : Theme.label)
                            .frame(maxWidth: .infinity).frame(height: 35)
                        Rectangle()
                            .fill(tab == item ? Theme.accent : .clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .background(Theme.mutedBG)
        .overlay(Rectangle().fill(Theme.hairline).frame(height: 1), alignment: .bottom)
    }
}
