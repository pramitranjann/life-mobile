import AppIntents
import PRLifeKit

struct StopCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop PR Life Capture"
    static var openAppWhenRun = false

    @MainActor func perform() async throws -> some IntentResult {
        await IntentBridge.coordinator?.handle(.stopCapture)
        await IntentBridge.activity?.update("Processing")
        await IntentBridge.activity?.end()
        return .result()
    }
}
