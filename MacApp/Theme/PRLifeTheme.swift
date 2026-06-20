import SwiftUI
import PRLifeKit

extension Color {
    init(hex: String) {
        let v = UInt64(hex, radix: 16) ?? 0
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xff) / 255,
                  green: Double((v >> 8) & 0xff) / 255,
                  blue: Double(v & 0xff) / 255, opacity: 1)
    }
}

enum Theme {
    static let bg       = Color(hex: PRLifeTokens.Color.background)
    static let panel    = Color(hex: PRLifeTokens.Color.panel)
    static let mutedBG  = Color(hex: PRLifeTokens.Color.mutedBG)
    static let border   = Color(hex: PRLifeTokens.Color.border)
    static let hairline = Color(hex: PRLifeTokens.Color.hairline)
    static let text     = Color(hex: PRLifeTokens.Color.text)
    static let muted    = Color(hex: PRLifeTokens.Color.muted)
    static let label    = Color(hex: PRLifeTokens.Color.label)
    static let accent   = Color(hex: PRLifeTokens.Color.accent)
    static let green    = Color(hex: PRLifeTokens.Color.green)
    static let amber    = Color(hex: PRLifeTokens.Color.amber)
    static let danger   = Color(hex: PRLifeTokens.Color.danger)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name = weight == .medium ? "DMMono-Medium" : (weight == .light ? "DMMono-Light" : "DMMono-Regular")
        return .custom(name, size: size)
    }
    static func display(_ size: CGFloat) -> Font { .custom("ClashDisplay-Medium", size: size) }
    static func body(_ size: CGFloat) -> Font { .system(size: size) }

    // Spec extras (CODEX_PROMPT tokens not in the base bridge).
    static let panel2     = Color(hex: PRLifeTokens.Color.panel2)
    static let divider    = Color(hex: "161616")          // #161616 row dividers
    static let accentSoft = Color(hex: PRLifeTokens.Color.accent).opacity(0.07)
    static let accentLine = Color(hex: PRLifeTokens.Color.accent).opacity(0.35)

    /// Priority dot colors: high → danger, medium → amber, low → label.
    static func priorityColor(_ priority: LifeTaskPriority) -> Color {
        switch priority {
        case .high: return danger
        case .medium: return amber
        case .low: return label
        }
    }
}
