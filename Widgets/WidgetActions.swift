import AppIntents
import PRLifeKit
import WidgetKit

struct CompleteWidgetTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete PR Life Task"
    static var description = IntentDescription("Completes the selected task and refreshes PR Life widgets.")

    @Parameter(title: "Task ID")
    var taskID: String

    init() {
        taskID = ""
    }

    init(taskID: String) {
        self.taskID = taskID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let client = LifeAPIClient(configurationProvider: {
            (LifeAPIBaseURL.normalizedURL(from: KeychainConfig.baseURL), KeychainConfig.token)
        })
        _ = try await client.completeTask(id: taskID)
        LifeWidgetTimelineReloader.reloadUpcoming()
        return .result()
    }
}

// CAPTURE_/NOTE_ in the widget use plain `Link`s — OpenURLIntent returned
// from a widget Button(intent:) was unreliable, and Links do the same job.
