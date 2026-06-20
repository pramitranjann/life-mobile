import ActivityKit
import Foundation
import PRLifeKit

@MainActor
final class LiveActivityController {
    private var activity: Activity<RecordingAttributes>?

    func start(context: CaptureContext) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = RecordingAttributes(captureID: UUID().uuidString)
        let state = RecordingAttributes.ContentState(startedAt: .now, statusLabel: "Recording",
                                                     contextName: context.displayName)
        activity = try? Activity.request(attributes: attrs, content: .init(state: state, staleDate: nil))
    }

    func update(_ label: String) async {
        guard let activity else { return }
        var s = activity.content.state; s.statusLabel = label
        await activity.update(.init(state: s, staleDate: nil))
    }

    func end() async {
        await activity?.end(nil, dismissalPolicy: .after(.now + 2)); activity = nil
    }
}
