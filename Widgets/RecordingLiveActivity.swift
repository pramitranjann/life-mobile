import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingAttributes.self) { ctx in
            HStack {
                Circle().fill(Color(red: 1, green: 0.19, blue: 0.13)).frame(width: 8, height: 8)
                Text(ctx.state.statusLabel).font(.system(size: 13))
                Spacer()
                Text(ctx.state.startedAt, style: .timer).monospacedDigit().font(.system(size: 15, weight: .medium))
                Button(intent: StopCaptureIntent()) {
                    Text("Stop").font(.system(size: 13, weight: .medium))
                }
                .tint(Color(red: 1, green: 0.19, blue: 0.13))
            }
            .padding(14).activityBackgroundTint(Color.black).activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text(ctx.state.statusLabel) }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(ctx.state.startedAt, style: .timer).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Button(intent: StopCaptureIntent()) {
                        Text("Stop Recording").frame(maxWidth: .infinity)
                    }
                    .tint(Color(red: 1, green: 0.19, blue: 0.13))
                }
            } compactLeading: {
                Circle().fill(Color(red: 1, green: 0.19, blue: 0.13)).frame(width: 8, height: 8)
            } compactTrailing: {
                Text(ctx.state.startedAt, style: .timer).monospacedDigit()
            } minimal: {
                Circle().fill(Color(red: 1, green: 0.19, blue: 0.13)).frame(width: 8, height: 8)
            }
        }
    }
}
