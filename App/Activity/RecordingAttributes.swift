import ActivityKit
import Foundation

enum RecordingActivityPhase: String, Codable, Hashable {
    case recording
    case processing
    case saved
}

struct RecordingAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var startedAt: Date
        var statusLabel: String
        var contextName: String
        var phase: RecordingActivityPhase
    }
    var captureID: String
}
