import SwiftUI
import UIKit

enum BNBUAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let defaultsKey = "bnbu.appearance.mode.v3"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色模式"
        case .dark: return "深色模式"
        }
    }

    var subtitle: String {
        switch self {
        case .system: return "随设备外观自动切换"
        case .light: return "明亮蓝白，适合日间使用"
        case .dark: return "深海军蓝，适合运动场景"
        }
    }

    var symbolName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.stars.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// `preferredColorScheme` only re-resolves the views it encloses. Sheets and
    /// alerts are hosted by their own presentation controllers, so switching the
    /// mode from the settings sheet left that sheet on the previous palette
    /// until it was dismissed. Overriding the style on the window covers every
    /// presentation, including the one the switch lives in.
    @MainActor
    func applyToWindows() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = interfaceStyle
            }
        }
    }
}

enum BNBULanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese
    case english

    static let defaultsKey = "bnbu.language.mode.v1"
    static let defaultMode: BNBULanguage = .system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "系统"
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        }
    }

    var locale: Locale {
        switch self {
        case .system: return .autoupdatingCurrent
        case .simplifiedChinese: return Locale(identifier: "zh-Hans")
        case .english: return Locale(identifier: "en")
        }
    }

    /// The student app currently ships Simplified Chinese and English.
    /// Treat every Chinese system language as Simplified Chinese and use
    /// English for all other system languages instead of falling back to the
    /// development language.
    static func supportedSystemLocaleIdentifier(
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        guard let preferredLanguage = preferredLanguages.first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !preferredLanguage.isEmpty else {
            return english.locale.identifier
        }
        return preferredLanguage.hasPrefix("zh")
            ? simplifiedChinese.locale.identifier
            : english.locale.identifier
    }
}

@MainActor
final class BNBULanguageSettings: ObservableObject {
    @Published private(set) var mode: BNBULanguage

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: BNBULanguage.defaultsKey)
            .flatMap(BNBULanguage.init(rawValue:))
            ?? .defaultMode
    }

    func select(rawValue: String) {
        guard let selectedMode = BNBULanguage(rawValue: rawValue),
              selectedMode != mode else {
            return
        }
        mode = selectedMode
        defaults.set(selectedMode.rawValue, forKey: BNBULanguage.defaultsKey)
    }
}

/// Resolves localized strings for code outside the SwiftUI locale
/// environment (AppState errors, validation rules, repository messages).
/// Follows the same in-app language override as the view layer, so
/// client-generated messages match the interface language. Server-returned
/// text is never routed through here and stays verbatim.
enum BNBUL10n {
    /// Tests pin a locale so exact-string assertions stay deterministic
    /// regardless of the host machine's language.
    nonisolated(unsafe) static var localeOverride: Locale?

    static var locale: Locale {
        if let localeOverride { return localeOverride }
        let mode = UserDefaults.standard.string(forKey: BNBULanguage.defaultsKey)
            .flatMap(BNBULanguage.init(rawValue:)) ?? .defaultMode
        switch mode {
        case .simplifiedChinese, .english:
            return mode.locale
        case .system:
            return Locale(identifier: BNBULanguage.supportedSystemLocaleIdentifier())
        }
    }

    static func text(_ key: String.LocalizationValue) -> String {
        // The locale argument of String(localized:) only affects value
        // formatting; the translation language comes from the bundle, so the
        // language-specific .lproj bundle must be loaded explicitly.
        String(localized: key, bundle: languageBundle, locale: locale)
    }

    /// Localizes a runtime key such as a server enum value. Unknown values are
    /// returned unchanged so names and other free-form server content remain
    /// verbatim.
    static func dynamicText(_ key: String) -> String {
        languageBundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func formatted(_ key: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }

    static func hourText(_ value: Double) -> String {
        let number: String
        if value.rounded(.down) == value {
            number = String(Int(value))
        } else {
            number = String(format: "%.1f", locale: locale, value)
        }
        return locale.identifier.hasPrefix("zh") ? "\(number) 小时" : "\(number) hr"
    }

    static var languageBundle: Bundle {
        let code = locale.identifier.hasPrefix("zh") ? "zh-Hans" : "en"
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}

/// "Just now" sentinel written into freshly created records/notifications.
/// Stored values may be either language, so the freshness check accepts both.
enum RecentTimestamp {
    static var justNow: String { BNBUL10n.text("刚刚") }

    static func isJustNow(_ value: String) -> Bool {
        value.hasPrefix("刚刚") || value.lowercased().hasPrefix("just now")
    }
}

/// Layout rhythm copied from Android `BNBULayout` (designsystem/Layout.kt).
/// dp values map 1:1 onto pt.
enum BNBUSpacing {
    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24
    static let space28: CGFloat = 28
    static let space32: CGFloat = 32

    /// Left/right margin of every root tab and auth page.
    static let screen: CGFloat = 20
    /// `SwissPanel` default inset.
    static let panel: CGFloat = 18
    static let touchTarget: CGFloat = 48
    static let primaryControlHeight: CGFloat = 52

    static let item: CGFloat = 16
    static let section: CGFloat = 12
    static let buttonGap: CGFloat = 10
    static let bottomSpacer: CGFloat = 28
}

/// Radius scale copied from Android `BNBUShapes` (designsystem/Shape.kt).
enum BNBURadius {
    static let extraSmall: CGFloat = 8
    static let small: CGFloat = 10
    static let medium: CGFloat = 14
    static let large: CGFloat = 18
    static let extraLarge: CGFloat = 24
    /// Pill used by `StatusBadge`; Android reuses `extraLarge` on a short capsule.
    static let pill: CGFloat = 24
}

/// Motion rhythm copied from Android `BNBUMotion` (designsystem/Motion.kt).
enum BNBUMotion {
    static let quick: Double = 0.12
    static let stateChange: Double = 0.18
    static let standard: Double = 0.22
    static let emphasized: Double = 0.32
    static let progress: Double = 0.36

    static let pressedScale: CGFloat = 0.97
    static let pressedOpacity: Double = 0.92
}

enum BNBUTheme {
    // Colours copied from the Android baseline `Theme.kt` colour schemes.
    // Android is the single source of truth for the cross-platform look, so
    // these must stay literal rather than being re-derived per platform.
    static let primary = Color.adaptive(light: 0x007AFF, dark: 0x0A84FF)
    static let onPrimary = Color.adaptive(light: 0xFFFFFF, dark: 0xFFFFFF)
    static let primaryContainer = Color.adaptive(light: 0xE8F2FF, dark: 0x16395F)
    static let onPrimaryContainer = Color.adaptive(light: 0x003E7D, dark: 0xD6E9FF)

    static let secondary = Color.adaptive(light: 0xFF9500, dark: 0xFF9F0A)
    static let onSecondary = Color.adaptive(light: 0xFFFFFF, dark: 0x2C1A00)
    static let secondaryContainer = Color.adaptive(light: 0xFFF1D6, dark: 0x503500)
    static let onSecondaryContainer = Color.adaptive(light: 0x5A3500, dark: 0xFFE2A8)

    static let tertiary = Color.adaptive(light: 0x248A3D, dark: 0x30D158)
    static let onTertiary = Color.adaptive(light: 0xFFFFFF, dark: 0x002C0D)
    static let tertiaryContainer = Color.adaptive(light: 0xE6F6E9, dark: 0x164B24)
    static let onTertiaryContainer = Color.adaptive(light: 0x0E4B1D, dark: 0xC7F5D0)

    static let error = Color.adaptive(light: 0xFF3B30, dark: 0xFF453A)
    static let onError = Color.adaptive(light: 0xFFFFFF, dark: 0xFFFFFF)
    static let errorContainer = Color.adaptive(light: 0xFFE9E7, dark: 0x5C201D)
    static let onErrorContainer = Color.adaptive(light: 0x7A1712, dark: 0xFFD2CE)

    static let background = Color.adaptive(light: 0xF2F2F7, dark: 0x000000)
    static let onBackground = Color.adaptive(light: 0x1C1C1E, dark: 0xF2F2F7)
    static let surface = Color.adaptive(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let onSurface = Color.adaptive(light: 0x1C1C1E, dark: 0xF2F2F7)
    static let surfaceVariant = Color.adaptive(light: 0xEFEFF4, dark: 0x2C2C2E)
    static let onSurfaceVariant = Color.adaptive(light: 0x636366, dark: 0xAEAEB2)
    static let outline = Color.adaptive(light: 0x8E8E93, dark: 0x8E8E93)
    static let outlineVariant = Color.adaptive(light: 0xC6C6C8, dark: 0x3A3A3C)

    /// Input fill, segmented-control track and quiet button fill.
    static let surfaceContainerLow = Color.adaptive(light: 0xF8F8FA, dark: 0x141416)
    static let surfaceContainerHigh = Color.adaptive(light: 0xE9E9EE, dark: 0x242426)
    static let surfaceContainerHighest = Color.adaptive(light: 0xE3E3E8, dark: 0x2C2C2E)

    /// The official BNBU identity blue does not follow the appearance mode.
    static let officialBlue = Color(hex: 0x0166A4)
    /// Camera scan and video cover scrims.
    static let overlayBlack = Color.black

    // Compatibility aliases while feature views migrate to semantic token names.
    static let ink = onSurface
    static let paper = background
    static let muted = onSurfaceVariant
    static let line = outlineVariant
    static let blue = primary
    static let blueLight = secondary
    static let blueSoft = primaryContainer
    static let pale = surfaceVariant
    static let warn = secondary
    static let good = tertiary
}

/// Type scale copied from Android `BNBUTypography` (designsystem/Type.kt).
/// Android sp maps onto pt; the platform sans font is SF on iOS. Sizes are
/// fixed rather than semantic so the cross-platform hierarchy matches.
enum BNBUFont {
    static let displayLarge = Font.system(size: 40, weight: .semibold)
    static let displayMedium = Font.system(size: 36, weight: .semibold)
    static let displaySmall = Font.system(size: 32, weight: .semibold)

    static let headlineLarge = Font.system(size: 30, weight: .bold)
    static let headlineMedium = Font.system(size: 26, weight: .semibold)
    static let headlineSmall = Font.system(size: 22, weight: .semibold)

    static let titleLarge = Font.system(size: 20, weight: .semibold)
    static let titleMedium = Font.system(size: 17, weight: .semibold)
    static let titleSmall = Font.system(size: 15, weight: .semibold)

    static let bodyLarge = Font.system(size: 17, weight: .regular)
    static let bodyMedium = Font.system(size: 15, weight: .regular)
    static let bodySmall = Font.system(size: 13, weight: .regular)

    static let labelLarge = Font.system(size: 17, weight: .semibold)
    static let labelMedium = Font.system(size: 13, weight: .medium)
    static let labelSmall = Font.system(size: 11, weight: .medium)

    /// Android sets an explicit line height per style; SwiftUI expresses the
    /// difference from the font's natural leading as extra line spacing.
    enum LineSpacing {
        static let displayLarge: CGFloat = 6
        static let headlineSmall: CGFloat = 6
        static let titleMedium: CGFloat = 5
        static let bodyLarge: CGFloat = 7
        static let bodyMedium: CGFloat = 6
        static let bodySmall: CGFloat = 5
    }

    /// Android applies negative tracking to the large styles.
    enum Tracking {
        static let displayLarge: CGFloat = -0.6
        static let displayMedium: CGFloat = -0.5
        static let displaySmall: CGFloat = -0.4
        static let headlineLarge: CGFloat = -0.35
        static let headlineMedium: CGFloat = -0.25
        static let headlineSmall: CGFloat = -0.15
        static let titleLarge: CGFloat = -0.1
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    static func adaptive(light: UInt, dark: UInt) -> Color {
        Color(
            UIColor { traits in
                UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
            }
        )
    }
}

private extension UIColor {
    convenience init(hex: UInt) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}

extension Double {
    var hourText: String {
        if rounded(.down) == self {
            return "\(Int(self))h"
        }
        return String(format: "%.1fh", self)
    }

    var localizedHourText: String {
        BNBUL10n.hourText(self)
    }
}
