import AppIntents
import PRLifeKit

struct StopCaptureIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop PR Life Capture"

    @MainActor func perform() async throws -> some IntentResult {
        await CaptureActionRouter.stop?()
        return .result()
    }
}
