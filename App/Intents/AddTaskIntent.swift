import AppIntents
import Foundation
import PRLifeKit

struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add a Task to PR Life"
    static var description = IntentDescription("Saves a task with an optional project and due date.")

    @Parameter(title: "Title", requestValueDialog: "What is the task?")
    var taskTitle: String

    @Parameter(title: "Project", requestValueDialog: "Which project should this go to?")
    var project: String?

    @Parameter(title: "Due Date", kind: .date)
    var dueDate: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$taskTitle) to \(\.$project) due \(\.$dueDate)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let environment = CaptureEnvironment.shared
        do {
            let project = PRLifeIntentSupport.normalizedProject(project)
            let result = try await environment.coordinator.createTask(
                title: taskTitle,
                projectSlug: project,
                dueLocalDate: PRLifeIntentSupport.dueLocalDate(dueDate)
            )
            environment.updatePendingCaptureCount()
            let message = PRLifeIntentSupport.savedMessage(
                kind: "task",
                project: project,
                disposition: result
            )
            return .result(dialog: "\(message)")
        } catch {
            return .result(dialog: "The task could not be saved: \(error.localizedDescription)")
        }
    }
}
