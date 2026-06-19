import Foundation

/// The single internal action vocabulary every input source maps to.
public enum PRLifeAction: Equatable, Sendable {
    case startCapture(context: CaptureContext)
    case stopCapture
}
