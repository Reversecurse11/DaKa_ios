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
}

enum BNBUSpacing {
    static let screen: CGFloat = 18
    static let panel: CGFloat = 16
    static let item: CGFloat = 16
    static let section: CGFloat = 12
    static let buttonGap: CGFloat = 10
    static let bottomSpacer: CGFloat = 40
}

enum BNBURadius {
    static let extraSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let extraLarge: CGFloat = 28
}

enum BNBUTheme {
    // BNBU Sports Design System v1.0 — Quick Reference tokens.
    static let primary = Color.adaptive(light: 0x1A73E8, dark: 0x8AB4F8)
    static let onPrimary = Color.adaptive(light: 0xFFFFFF, dark: 0x041E49)
    static let primaryContainer = Color.adaptive(light: 0xD3E3FD, dark: 0x0842A0)
    static let onPrimaryContainer = Color.adaptive(light: 0x041E49, dark: 0xD3E3FD)

    static let secondary = Color.adaptive(light: 0xFD7E14, dark: 0xFFB77C)
    static let secondaryContainer = Color.adaptive(light: 0xFFDCC2, dark: 0x5C2D00)
    static let tertiary = Color.adaptive(light: 0x00897B, dark: 0x80CBC4)

    static let error = Color.adaptive(light: 0xD93025, dark: 0xFFB4AB)
    static let errorContainer = Color.adaptive(light: 0xF9DEDC, dark: 0x93000A)

    static let background = Color.adaptive(light: 0xF8F9FA, dark: 0x0F172A)
    static let surface = Color.adaptive(light: 0xFFFFFF, dark: 0x1E2433)
    static let onSurface = Color.adaptive(light: 0x202124, dark: 0xE2E2E3)
    static let surfaceVariant = Color.adaptive(light: 0xF1F3F9, dark: 0x2A3142)
    static let onSurfaceVariant = Color.adaptive(light: 0x44474E, dark: 0xC4C6D0)
    static let outline = Color.adaptive(light: 0x747775, dark: 0x8E918F)

    // Compatibility aliases while feature views migrate to semantic token names.
    static let ink = onSurface
    static let paper = background
    static let muted = onSurfaceVariant
    static let line = outline
    static let blue = primary
    static let blueLight = secondary
    static let blueSoft = primaryContainer
    static let pale = surfaceVariant
    static let warn = secondary
    static let good = tertiary
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
}
