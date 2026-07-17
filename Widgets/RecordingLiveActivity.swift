import ActivityKit
import WidgetKit
import SwiftUI
import PRLifeKit
import AppIntents

private struct QuickCaptureEntry: TimelineEntry {
    let date: Date
}

private struct QuickCaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickCaptureEntry { QuickCaptureEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (QuickCaptureEntry) -> Void) {
        completion(QuickCaptureEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickCaptureEntry>) -> Void) {
        completion(Timeline(entries: [QuickCaptureEntry(date: .now)], policy: .never))
    }
}

struct QuickCaptureWidget: Widget {
    private let deepLink = URL(string: "prlife://capture?context=quick")!

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PRLifeQuickCapture", provider: QuickCaptureProvider()) { _ in
            QuickCaptureWidgetView()
                .widgetURL(deepLink)
        }
        .configurationDisplayName("Quick Capture")
        .description("Start a PR Life recording from the Home or Lock Screen.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

private struct QuickCaptureWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Text("PR LIFE · Start recording")
            case .accessoryCircular:
                ZStack {
                    Circle().fill(Theme.bg)
                    Circle().stroke(Theme.accentLine, lineWidth: 1)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            case .accessoryRectangular:
                HStack(spacing: 10) {
                    ZStack {
                        Rectangle().fill(Theme.bg)
                        Rectangle().stroke(Theme.accentLine, lineWidth: 1)
                        Text("PR_")
                            .font(Theme.mono(10, .medium))
                            .foregroundStyle(Theme.accent)
                    }
                    .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("PR LIFE_")
                            .font(Theme.mono(12, .medium))
                        Text("Tap to record")
                            .font(Theme.mono(11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.vertical, 4)
            default:
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Circle().fill(Theme.accent).frame(width: 10, height: 10)
                        Spacer()
                        Image(systemName: "mic.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                    Spacer()
                    Text("Quick Capture")
                        .font(Theme.display(16))
                        .foregroundStyle(Theme.text)
                    Text("Start recording in PR Life.")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.label)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(14)
            }
        }
        .containerBackground(for: .widget) {
            switch family {
            case .systemSmall:
                Theme.bg
            default:
                Color.clear
            }
        }
    }
}

struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingAttributes.self) { ctx in
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        ZStack {
                            Rectangle().fill(Theme.panel)
                            Rectangle().stroke(Theme.accentLine, lineWidth: 1)
                            Text("PR_")
                                .font(Theme.mono(10, .medium))
                                .foregroundStyle(Theme.accent)
                        }
                        .frame(width: 42, height: 42)

                        Text("PR LIFE_")
                            .font(Theme.mono(18, .medium))
                            .foregroundStyle(Theme.text)
                    }
                    Text(ctx.state.statusLabel)
                        .font(Theme.mono(14, .medium))
                        .foregroundStyle(Theme.text)
                    Text(ctx.state.contextName.uppercased())
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.label)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 10) {
                    if ctx.state.phase == .recording {
                        HStack(spacing: 8) {
                            Circle().fill(Theme.accent).frame(width: 10, height: 10)
                            Text(ctx.state.startedAt, style: .timer)
                                .monospacedDigit()
                                .font(Theme.mono(20, .medium))
                                .foregroundStyle(Theme.accent)
                        }
                        Button(intent: StopCaptureIntent()) {
                            // Solid accent = live/recording state, per the web `.life-mic.is-live`.
                            Text("STOP_")
                                .font(Theme.mono(12, .medium))
                                .foregroundStyle(Theme.bg)
                                .frame(minWidth: 74, minHeight: 32)
                                .background(Rectangle().fill(Theme.accent))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Image(systemName: ctx.state.phase == .saved ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .activityBackgroundTint(Theme.bg)
            .activitySystemActionForegroundColor(Theme.text)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ctx.state.statusLabel)
                            .font(Theme.mono(13, .medium))
                        Text(ctx.state.contextName.uppercased())
                            .font(Theme.mono(11))
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if ctx.state.phase == .recording {
                        Text(ctx.state.startedAt, style: .timer)
                            .monospacedDigit()
                            .font(Theme.mono(16, .medium))
                    } else {
                        Image(systemName: ctx.state.phase == .saved ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                            .foregroundStyle(Theme.accent)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if ctx.state.phase == .recording {
                        Button(intent: StopCaptureIntent()) {
                            Text("STOP RECORDING_")
                                .font(Theme.mono(12, .medium))
                                .foregroundStyle(Theme.bg)
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background(Rectangle().fill(Theme.accent))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(ctx.state.phase == .saved ? "Saved. Ready for next capture." : "Saving and uploading...")
                            .font(Theme.mono(12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } compactLeading: {
                Circle().fill(Theme.accent).frame(width: 8, height: 8)
            } compactTrailing: {
                if ctx.state.phase == .recording {
                    Text(ctx.state.startedAt, style: .timer)
                        .monospacedDigit()
                        .font(Theme.mono(12, .medium))
                } else {
                    Image(systemName: ctx.state.phase == .saved ? "checkmark" : "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                }
            } minimal: {
                Image(systemName: ctx.state.phase == .saved ? "checkmark.circle.fill" : "mic.fill")
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}
