import ActivityKit
import Foundation

struct RecordingAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var startedAt: Date
        var statusLabel: String   // "Recording", "Processing", "Uploading", "Done"
        var contextName: String
    }
    var captureID: String
}
