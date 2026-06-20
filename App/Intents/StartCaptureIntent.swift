import AppIntents
import PRLifeKit

struct StartCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Start PR Life Capture"
    static var openAppWhenRun = true     // launching gives us a reliable audio session

    @Parameter(title: "Context") var context: CaptureContextAppEnum?

    @MainActor func perform() async throws -> some IntentResult {
        _ = CaptureEnvironment.shared          // force env init (sets the router) on cold launch
        let ctx = (context ?? .quick).kit
        await CaptureActionRouter.start?(ctx)
        return .result()
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
