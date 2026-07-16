import AppIntents
import PRLifeKit

struct StopCaptureIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop PR Life Capture"

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let message: String
        if let stop = CaptureActionRouter.stop {
            await stop()
            message = "PR Life capture stopped and saved for processing."
        } else {
            CaptureControlChannel.requestStop()
            message = "I sent the stop request to PR Life."
        }
        return .result(dialog: "\(message)")
    }
}
