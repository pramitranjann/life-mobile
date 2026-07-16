import AppIntents
import PRLifeKit

struct AddNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Add a Note to PR Life"
    static var description = IntentDescription("Saves a dictated note, optionally linked to a project.")

    @Parameter(title: "Note", requestValueDialog: "What should the note say?")
    var content: String

    @Parameter(title: "Project", requestValueDialog: "Which project should this go to?")
    var project: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$content) to \(\.$project)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let environment = CaptureEnvironment.shared
        do {
            let project = PRLifeIntentSupport.normalizedProject(project)
            let result = try await environment.coordinator.createNote(
                content: content,
                projectSlug: project
            )
            environment.updatePendingCaptureCount()
            let message = PRLifeIntentSupport.savedMessage(
                kind: "note",
                project: project,
                disposition: result
            )
            return .result(dialog: "\(message)")
        } catch {
            return .result(dialog: "The note could not be saved: \(error.localizedDescription)")
        }
    }
}
