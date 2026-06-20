import ActivityKit
import Foundation
import PRLifeKit

@MainActor
final class LiveActivityController {
    private var activity: Activity<RecordingAttributes>?

    func start(context: CaptureContext) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = RecordingAttributes(captureID: UUID().uuidString)
        let state = RecordingAttributes.ContentState(
            startedAt: .now,
            statusLabel: "RECORDING_",
            contextName: context.displayName,
            phase: .recording
        )
        activity = try? Activity.request(attributes: attrs, content: .init(state: state, staleDate: nil))
    }

    func update(_ label: String,
                phase: RecordingActivityPhase? = nil,
                contextName: String? = nil) async {
        guard let activity else { return }
        var s = activity.content.state
        s.statusLabel = label
        if let phase { s.phase = phase }
        if let contextName { s.contextName = contextName }
        await activity.update(.init(state: s, staleDate: nil))
    }

    func end(finalLabel: String? = nil,
             finalPhase: RecordingActivityPhase? = nil,
             finalContextName: String? = nil,
             dismissAfter delay: TimeInterval = 2) async {
        guard let activity else { return }
        var finalState = activity.content.state
        if let finalLabel { finalState.statusLabel = finalLabel }
        if let finalPhase { finalState.phase = finalPhase }
        if let finalContextName { finalState.contextName = finalContextName }
        await activity.end(.init(state: finalState, staleDate: nil),
                           dismissalPolicy: .after(.now + delay))
        self.activity = nil
    }
}
