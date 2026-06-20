import ActivityKit
import WidgetKit
import SwiftUI
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
                Text("PR LIFE  Start recording")
            case .accessoryCircular:
                ZStack {
                    Circle().fill(Color.black)
                    Circle().stroke(Color(red: 1, green: 0.19, blue: 0.13).opacity(0.45), lineWidth: 1)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(red: 1, green: 0.19, blue: 0.13))
                }
            case .accessoryRectangular:
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.black.opacity(0.95))
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color(red: 1, green: 0.19, blue: 0.13).opacity(0.4), lineWidth: 1)
                        Text("PR_")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 1, green: 0.19, blue: 0.13))
                    }
                    .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("PR LIFE")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        Text("Tap to record")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 1, green: 0.19, blue: 0.13))
                }
                .padding(.vertical, 4)
            default:
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Circle().fill(Color(red: 1, green: 0.19, blue: 0.13)).frame(width: 10, height: 10)
                        Spacer()
                        Image(systemName: "mic.fill").font(.system(size: 16, weight: .medium))
                    }
                    Spacer()
                    Text("Quick Capture").font(.system(size: 16, weight: .semibold))
                    Text("Start recording in PR Life.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(14)
            }
        }
        .containerBackground(for: .widget) {
            switch family {
            case .systemSmall:
                Color.black
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
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.black.opacity(0.85))
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(Color(red: 1, green: 0.19, blue: 0.13).opacity(0.35), lineWidth: 1)
                            Text("PR_")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(red: 1, green: 0.19, blue: 0.13))
                        }
                        .frame(width: 42, height: 42)

                        Text("PR LIFE")
                            .font(.system(size: 18, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.95))
                    }
                    Text(ctx.state.statusLabel)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(ctx.state.contextName.uppercased())
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 10) {
                    if ctx.state.phase == .recording {
                        HStack(spacing: 8) {
                            Circle().fill(Color(red: 1, green: 0.19, blue: 0.13)).frame(width: 10, height: 10)
                            Text(ctx.state.startedAt, style: .timer)
                                .monospacedDigit()
                                .font(.system(size: 20, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(red: 1, green: 0.19, blue: 0.13))
                        }
                        Button(intent: StopCaptureIntent()) {
                            Text("STOP")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .frame(minWidth: 74)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 1, green: 0.19, blue: 0.13))
                    } else {
                        Image(systemName: ctx.state.phase == .saved ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Color(red: 1, green: 0.19, blue: 0.13))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .activityBackgroundTint(Color(red: 0.06, green: 0.04, blue: 0.04))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ctx.state.statusLabel)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        Text(ctx.state.contextName.uppercased())
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if ctx.state.phase == .recording {
                        Text(ctx.state.startedAt, style: .timer)
                            .monospacedDigit()
                            .font(.system(size: 16, weight: .medium, design: .monospaced))
                    } else {
                        Image(systemName: ctx.state.phase == .saved ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                            .foregroundStyle(Color(red: 1, green: 0.19, blue: 0.13))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if ctx.state.phase == .recording {
                        Button(intent: StopCaptureIntent()) {
                            Text("STOP RECORDING_").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 1, green: 0.19, blue: 0.13))
                    } else {
                        Text(ctx.state.phase == .saved ? "Saved. Ready for next capture." : "Saving and uploading...")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } compactLeading: {
                Circle().fill(Color(red: 1, green: 0.19, blue: 0.13)).frame(width: 8, height: 8)
            } compactTrailing: {
                if ctx.state.phase == .recording {
                    Text(ctx.state.startedAt, style: .timer)
                        .monospacedDigit()
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                } else {
                    Image(systemName: ctx.state.phase == .saved ? "checkmark" : "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                }
            } minimal: {
                Image(systemName: ctx.state.phase == .saved ? "checkmark.circle.fill" : "mic.fill")
                    .foregroundStyle(Color(red: 1, green: 0.19, blue: 0.13))
            }
        }
    }
}
