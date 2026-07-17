import Foundation

public enum PRLifeTokens {
    public enum Color {
        public static let background = "0A0A0A"
        public static let panel      = "111111"
        public static let panel2     = "141414"
        public static let mutedBG    = "0D0D0D"
        public static let border     = "232323"
        public static let hairline   = "1C1C1C"
        public static let divider    = "161616"
        public static let text       = "F5F2ED"
        public static let muted      = "A4A4A4"
        public static let label      = "6F6F6F"
        public static let transcript = "CFCCC6"
        public static let accent     = "FF3120"
        public static let green      = "5BD07A"
        public static let amber      = "F5A623"
        public static let danger     = "FF6C61"
    }
    /// Accent alphas from the web reference (globals.css .life-shell):
    /// --life-accent-soft: rgba(accent, 0.10), --life-accent-line: rgba(accent, 0.35).
    /// These are the ONLY two accent alphas in the system.
    public enum Alpha {
        public static let accentSoft = 0.10
        public static let accentLine = 0.35
    }
    public enum Spacing {
        public static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12
        public static let l: CGFloat = 16, xl: CGFloat = 20, xxl: CGFloat = 24
    }
}
