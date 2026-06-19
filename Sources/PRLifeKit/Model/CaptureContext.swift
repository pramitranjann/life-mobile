import Foundation

public enum CaptureContext: String, Codable, Sendable, CaseIterable {
    case quick
    case work
    case journal
    case ideas

    /// Maps to PR Life `projectSlug`. `quick` carries no project context.
    public var projectSlug: String? {
        self == .quick ? nil : rawValue
    }

    public var displayName: String {
        switch self {
        case .quick: return "Quick Capture"
        case .work: return "Work"
        case .journal: return "Journal"
        case .ideas: return "Ideas"
        }
    }
}
