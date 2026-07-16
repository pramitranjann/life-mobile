import AppIntents
import PRLifeKit

struct StartCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Start PR Life Capture"
    static var openAppWhenRun = true     // launching gives us a reliable audio session

    @Parameter(title: "Context") var context: CaptureContextAppEnum?

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let environment = CaptureEnvironment.shared // force init (sets router) on cold launch
        let ctx = (context ?? .quick).kit
        let wasRecording = environment.coordinator.isRecording
        await CaptureActionRouter.start?(ctx)
        guard environment.coordinator.isRecording else {
            return .result(dialog: "PR Life could not start recording. Open the app to check microphone access.")
        }
        if wasRecording {
            return .result(dialog: "PR Life is already recording.")
        }
        return .result(dialog: "Recording started — \(ctx.displayName).")
    }
}

enum CaptureContextAppEnum: String, AppEnum {
    case quick, work, journal, ideas
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Capture Context"
    static var caseDisplayRepresentations: [CaptureContextAppEnum: DisplayRepresentation] = [
        .quick: "Quick", .work: "Work", .journal: "Journal", .ideas: "Ideas"
    ]
    var kit: CaptureContext { CaptureContext(rawValue: rawValue) ?? .quick }
}
