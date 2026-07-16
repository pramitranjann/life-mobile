import AppIntents

struct NextInLifeIntent: AppIntent {
    static var title: LocalizedStringResource = "What's Next in PR Life?"
    static var description = IntentDescription("Reads the next event and top active task from PR Life.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let message = try await PRLifeIntentSupport.nextSummary(
                api: CaptureEnvironment.shared.api
            )
            return .result(dialog: "\(message)")
        } catch {
            return .result(dialog: "I couldn't read PR Life: \(error.localizedDescription)")
        }
    }
}
