import AppIntents
import PRLifeKit

struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete a PR Life Task"
    static var description = IntentDescription("Marks a matching active PR Life task complete.")

    @Parameter(title: "Task", requestValueDialog: "Which task did you complete?")
    var taskName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Complete \(\.$taskName)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let api = CaptureEnvironment.shared.api
        do {
            let tasks = try await api.fetchTasks()
            let task: LifeTask
            switch PRLifeIntentSupport.taskMatch(named: taskName, in: tasks) {
            case .found(let match):
                task = match
            case .ambiguous:
                return .result(dialog: "I found multiple active tasks matching \(taskName). Please use a more specific title.")
            case .notFound:
                return .result(dialog: "I couldn't find an active task matching \(taskName).")
            }
            let completed = try await api.completeTask(id: task.id)
            LifeWidgetTimelineReloader.reloadUpcoming()
            return .result(dialog: "Marked \(completed.title) complete in PR Life.")
        } catch {
            return .result(dialog: "The task could not be completed: \(error.localizedDescription)")
        }
    }
}
