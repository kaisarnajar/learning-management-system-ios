import SwiftUI
import UIKit

/*
 * The app's colours, ported 1:1 from Android's Theme.kt: the Material 3 scheme (light and dark) and the brand colours
 * outside it. Each token is a dynamic colour, so it follows the in-app appearance choice (applied at the root with
 * preferredColorScheme) as well as the phone's.
 */

extension UIColor {
    /// 0xRRGGBB or 0xAARRGGBB.
    convenience init(hex: UInt32) {
        let hasAlpha = hex > 0xFFFFFF
        let a = hasAlpha ? CGFloat((hex >> 24) & 0xFF) / 255 : 1
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: a
        )
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }

    /// A colour that is [light] in light mode and [dark] in dark mode.
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

/// The Material colour scheme roles the app uses (MaterialTheme.colorScheme on Android).
enum Scheme {
    static let primary = Color.dynamic(0x0F3D2E, 0x8FD5B6)
    static let onPrimary = Color.dynamic(0xFFFFFF, 0x00382A)
    static let primaryContainer = Color.dynamic(0xD3EFE1, 0x0F4D38)
    static let onPrimaryContainer = Color.dynamic(0x002116, 0xABF2D1)
    static let secondary = Color.dynamic(0x9A7B0A, 0xE9C349)
    static let onSecondary = Color.dynamic(0xFFFFFF, 0x3C2F00)
    static let secondaryContainer = Color.dynamic(0xF8EBC0, 0x544200)
    static let onSecondaryContainer = Color.dynamic(0x2E2400, 0xFFE08A)
    static let tertiary = Color.dynamic(0x3B6658, 0xA1CFBF)
    static let onTertiary = Color.dynamic(0xFFFFFF, 0x05372B)
    static let tertiaryContainer = Color.dynamic(0xBDEBDA, 0x234E41)
    static let onTertiaryContainer = Color.dynamic(0x002019, 0xBDEBDA)
    static let background = Color.dynamic(0xFBF9F4, 0x0E1412)
    static let onBackground = Color.dynamic(0x1B1C19, 0xE2E3DE)
    static let surface = Color.dynamic(0xFBF9F4, 0x0E1412)
    static let onSurface = Color.dynamic(0x1B1C19, 0xE2E3DE)
    static let surfaceVariant = Color.dynamic(0xE5E3DA, 0x3F4943)
    static let onSurfaceVariant = Color.dynamic(0x5B5E57, 0xBFC9C2)
    static let surfaceContainerLowest = Color.dynamic(0xFFFFFF, 0x090E0C)
    static let surfaceContainerLow = Color.dynamic(0xF7F4EC, 0x141A18)
    static let surfaceContainer = Color.dynamic(0xF2EFE7, 0x1A211E)
    static let surfaceContainerHigh = Color.dynamic(0xECE9E0, 0x242B28)
    static let surfaceContainerHighest = Color.dynamic(0xE6E3DA, 0x2F3633)
    static let outline = Color.dynamic(0x8A8D85, 0x89938D)
    static let outlineVariant = Color.dynamic(0xDDD9CD, 0x3F4943)
    static let error = Color.dynamic(0xB3261E, 0xF2B8B5)
    static let onError = Color.dynamic(0xFFFFFF, 0x601410)
    static let errorContainer = Color.dynamic(0xFBE3E1, 0x8C1D18)
    static let onErrorContainer = Color.dynamic(0x410E0B, 0xF9DEDC)
    static let inverseSurface = Color.dynamic(0x2F312D, 0xE2E3DE)
    static let inverseOnSurface = Color.dynamic(0xF2F0E9, 0x2F312D)
    static let inversePrimary = Color.dynamic(0x8FD5B6, 0x0F3D2E)
}

/// Brand colours outside the Material roles: gold accents, the hero green, status tones (BrandColors on Android).
enum Brand {
    static let gold = Color.dynamic(0x9A7B0A, 0xE9C349)
    static let goldSoft = Color(hex: 0xD4AF37)
    /// The website's PageHero gradient (#003527 → #002117).
    static let hero = Color.dynamic(0x003527, 0x0C3326)
    static let heroDeep = Color.dynamic(0x002117, 0x04170F)
    static let onHero = Color.dynamic(0xFFFFFF, 0xF3F1EA)
    static let mint = Color.dynamic(0x7FD1AE, 0x8FD5B6)
    static let success = Color.dynamic(0x1E6B47, 0x8FD5B6)
    static let successContainer = Color.dynamic(0xDDF2E6, 0x173A2B)
    static let warning = Color.dynamic(0x8A5A00, 0xF2C46D)
    static let warningContainer = Color.dynamic(0xFCEFCF, 0x3D2E0C)
    /// The website's info tone is violet (violet-900 on violet-100).
    static let info = Color.dynamic(0x4C1D95, 0xC4B5FD)
    static let infoContainer = Color.dynamic(0xEDE9FE, 0x2E1065)
    static let danger = Color.dynamic(0xB3261E, 0xF2B8B5)
    static let dangerContainer = Color.dynamic(0xFBE3E1, 0x4A1816)
    static let outlineSoft = Color.dynamic(0xE7E2D6, 0x29322E)
    /// Call-to-action buttons: the website's gold (--primary), with dark text so the label stays readable (AA).
    static let cta = Color(hex: 0xD4A017)
    static let onCta = Color(hex: 0x1A1A1A)
    /// The thin band shown while the debug build is on staging.
    static let stagingAmber = Color(hex: 0xB45309)
    /// The card's soft shadow (black at 12%).
    static let cardShadow = Color.black.opacity(0.12)
}
