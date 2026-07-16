import Foundation

public enum CaptureStatus: String, Codable, Sendable, CaseIterable {
    case recording
    case processing   // transcribing
    case reviewing    // transcript is durable and awaiting explicit save
    case uploading
    case done
    case failed

    public var isTerminal: Bool { self == .done || self == .failed }

    /// Display label used in the UI status badge, e.g. "PROCESSING_".
    public var badgeLabel: String {
        switch self {
        case .recording: return "RECORDING_"
        case .processing: return "PROCESSING_"
        case .reviewing: return "REVIEW_"
        case .uploading: return "UPLOADING_"
        case .done: return "DONE_"
        case .failed: return "FAILED_"
        }
    }
}
