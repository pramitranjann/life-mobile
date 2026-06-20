import Foundation
import CoreText

/// Registers the bundled custom fonts at launch so `Font.custom(...)` resolves them.
/// macOS doesn't read the iOS `UIAppFonts` key, and Info.plist `ATSApplicationFontsPath`
/// depends on bundle layout — runtime registration via CTFontManager is layout-agnostic.
enum FontRegistration {
    private static let fonts: [(String, String)] = [
        ("ClashDisplay-Regular", "otf"),
        ("ClashDisplay-Medium", "otf"),
        ("ClashDisplay-Semibold", "otf"),
        ("ClashDisplay-Bold", "otf"),
        ("DMMono-Light", "ttf"),
        ("DMMono-Regular", "ttf"),
        ("DMMono-Medium", "ttf"),
    ]

    static func registerAll() {
        for (name, ext) in fonts {
            guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
