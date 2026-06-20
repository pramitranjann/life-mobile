import AppIntents
import PRLifeKit

struct StopCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop PR Life Capture"
    static var openAppWhenRun = false

    @MainActor func perform() async throws -> some IntentResult {
        await CaptureEnvironment.shared.coordinator.handle(.stopCapture)
        await CaptureEnvironment.shared.activity.update("Processing")
        await CaptureEnvironment.shared.activity.end()
        return .result()
    }
}
