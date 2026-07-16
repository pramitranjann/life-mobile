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

@available(iOS 18.0, *)
struct StartWidgetCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Start PR Life Capture"
    static var description = IntentDescription("Opens PR Life and starts a voice capture.")

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(LifeDeepLink.capture()))
    }
}

@available(iOS 18.0, *)
struct AddWidgetNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Add PR Life Note"
    static var description = IntentDescription("Opens PR Life's focused note composer.")

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(LifeDeepLink.note))
    }
}
