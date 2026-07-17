import SwiftUI

public extension Color {
    /// Hex bridge for PRLifeTokens values ("0A0A0A" → Color).
    init(hex: String) {
        let v = UInt64(hex, radix: 16) ?? 0
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xff) / 255,
                  green: Double((v >> 8) & 0xff) / 255,
                  blue: Double(v & 0xff) / 255, opacity: 1)
    }
}

/// The one SwiftUI bridge over PRLifeTokens, shared by the iOS app, Mac app,
/// and all widget targets. Values mirror the web reference (`.life-shell` in
/// the portfolio's globals.css) — that CSS is the source of truth.
public enum Theme {
    public static let bg       = Color(hex: PRLifeTokens.Color.background)
    public static let panel    = Color(hex: PRLifeTokens.Color.panel)
    public static let panel2   = Color(hex: PRLifeTokens.Color.panel2)
    public static let mutedBG  = Color(hex: PRLifeTokens.Color.mutedBG)
    public static let border   = Color(hex: PRLifeTokens.Color.border)
    public static let hairline = Color(hex: PRLifeTokens.Color.hairline)
    public static let divider  = Color(hex: PRLifeTokens.Color.divider)
    public static let text     = Color(hex: PRLifeTokens.Color.text)
    public static let muted    = Color(hex: PRLifeTokens.Color.muted)
    public static let label    = Color(hex: PRLifeTokens.Color.label)
    public static let transcript = Color(hex: PRLifeTokens.Color.transcript)
    public static let accent   = Color(hex: PRLifeTokens.Color.accent)
    public static let green    = Color(hex: PRLifeTokens.Color.green)
    public static let amber    = Color(hex: PRLifeTokens.Color.amber)
    public static let danger   = Color(hex: PRLifeTokens.Color.danger)

    public static let accentSoft = Color(hex: PRLifeTokens.Color.accent).opacity(PRLifeTokens.Alpha.accentSoft)
    public static let accentLine = Color(hex: PRLifeTokens.Color.accent).opacity(PRLifeTokens.Alpha.accentLine)

    /// Priority dot colors: high → danger, medium → amber, low → label.
    public static func priorityColor(_ priority: LifeTaskPriority) -> Color {
        switch priority {
        case .high: return danger
        case .medium: return amber
        case .low: return label
        }
    }

    public static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name = weight == .medium ? "DMMono-Medium" : (weight == .light ? "DMMono-Light" : "DMMono-Regular")
        return .custom(name, size: size)
    }
    public static func display(_ size: CGFloat) -> Font { .custom("ClashDisplay-Medium", size: size) }
    /// Content text. Mono-first, matching the web reference where DM Mono is
    /// the default family and Clash Display is reserved for large headings.
    public static func body(_ size: CGFloat) -> Font { mono(size) }
}

/// Press feedback for custom-drawn buttons: a quick opacity dip, interruptible,
/// mirroring the web's 0.1–0.15s transitions on every interactive surface.
public struct PRPressableButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == PRPressableButtonStyle {
    /// `.buttonStyle(.pressable)` — plain rendering plus pressed feedback.
    static var pressable: PRPressableButtonStyle { .init() }
}

/// Circular task checkbox per the web `.life-check`: 1.5px border, fills
/// accent with a dark check when done. Square checkboxes are off-system.
public struct TaskCheckbox: View {
    public var size: CGFloat
    public var isDone: Bool

    public init(size: CGFloat = 18, isDone: Bool = false) {
        self.size = size
        self.isDone = isDone
    }

    public var body: some View {
        ZStack {
            Circle().fill(isDone ? Theme.accent : Color.clear)
            Circle().strokeBorder(isDone ? Theme.accent : Theme.border, lineWidth: 1.5)
            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(Theme.bg)
            }
        }
        .frame(width: size, height: size)
    }
}

/// 7px priority dot per the web `.pri-dot`.
public struct PriorityDot: View {
    public let priority: LifeTaskPriority

    public init(priority: LifeTaskPriority) {
        self.priority = priority
    }

    public var body: some View {
        Circle()
            .fill(Theme.priorityColor(priority))
            .frame(width: 7, height: 7)
    }
}
