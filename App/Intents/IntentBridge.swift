import Foundation
import PRLifeKit

/// Set once at app launch so App Intents can route to the running coordinator/activity.
@MainActor
enum IntentBridge {
    static var coordinator: CaptureCoordinator?
    static var activity: LiveActivityController?
}
