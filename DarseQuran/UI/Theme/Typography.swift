import SwiftUI
import UIKit

/*
 * The type scale, ported from Android's Type.kt (Material 3 sizes with the app's overrides). Source Serif 4 for hero
 * and page titles, Poppins for everything else, Amiri for Arabic. Every style scales with Dynamic Type relative to the
 * closest iOS text style.
 */

enum FontName {
    static let serifSemiBold = "SourceSerif4Roman-SemiBold"
    static let serifRegular = "SourceSerif4Roman-Regular"
    static let serifItalic = "SourceSerif4Italic-Italic"
    static let sansRegular = "Poppins-Regular"
    static let sansMedium = "Poppins-Medium"
    /// Poppins Bold isn't bundled, so bold maps to SemiBold (as on Android).
    static let sansSemiBold = "Poppins-SemiBold"
    static let arabicRegular = "Amiri-Regular"
    static let arabicBold = "Amiri-Bold"
}

/// One text style: face, size, line height and letter spacing, as Compose's TextStyle.
struct AppTextStyle: Sendable {
    let fontName: String
    let size: CGFloat
    let lineHeight: CGFloat
    /// Letter spacing in points (Compose sp).
    let tracking: CGFloat
    let relativeTo: Font.TextStyle

    var font: Font { .custom(fontName, size: size, relativeTo: relativeTo) }

    var uiFont: UIFont { UIFont(name: fontName, size: size) ?? .systemFont(ofSize: size) }

    /// Extra space between lines so the line height matches Android's.
    var lineSpacing: CGFloat { max(0, lineHeight - uiFont.lineHeight) }

    func with(name: String? = nil, size: CGFloat? = nil, lineHeight: CGFloat? = nil, tracking: CGFloat? = nil) -> AppTextStyle {
        AppTextStyle(
            fontName: name ?? fontName,
            size: size ?? self.size,
            lineHeight: lineHeight ?? self.lineHeight,
            tracking: tracking ?? self.tracking,
            relativeTo: relativeTo
        )
    }
}

/// MaterialTheme.typography.
enum Typo {
    static let displayLarge = AppTextStyle(fontName: FontName.serifSemiBold, size: 57, lineHeight: 64, tracking: -0.25, relativeTo: .largeTitle)
    static let displayMedium = AppTextStyle(fontName: FontName.serifSemiBold, size: 45, lineHeight: 52, tracking: 0, relativeTo: .largeTitle)
    static let displaySmall = AppTextStyle(fontName: FontName.serifSemiBold, size: 36, lineHeight: 44, tracking: 0, relativeTo: .largeTitle)
    static let headlineLarge = AppTextStyle(fontName: FontName.serifSemiBold, size: 32, lineHeight: 40, tracking: 0, relativeTo: .largeTitle)
    static let headlineMedium = AppTextStyle(fontName: FontName.serifSemiBold, size: 26, lineHeight: 36, tracking: 0, relativeTo: .title)
    // Below the page title the website's headings are Poppins bold; Source Serif is kept for hero and page titles.
    static let headlineSmall = AppTextStyle(fontName: FontName.sansSemiBold, size: 22, lineHeight: 32, tracking: 0, relativeTo: .title2)
    static let titleLarge = AppTextStyle(fontName: FontName.sansSemiBold, size: 19, lineHeight: 28, tracking: 0, relativeTo: .title3)
    static let titleMedium = AppTextStyle(fontName: FontName.sansSemiBold, size: 15, lineHeight: 24, tracking: 0.15, relativeTo: .headline)
    static let titleSmall = AppTextStyle(fontName: FontName.sansSemiBold, size: 13, lineHeight: 20, tracking: 0.1, relativeTo: .subheadline)
    static let bodyLarge = AppTextStyle(fontName: FontName.sansRegular, size: 15, lineHeight: 24, tracking: 0.5, relativeTo: .body)
    static let bodyMedium = AppTextStyle(fontName: FontName.sansRegular, size: 14, lineHeight: 21, tracking: 0.25, relativeTo: .callout)
    static let bodySmall = AppTextStyle(fontName: FontName.sansRegular, size: 12, lineHeight: 17, tracking: 0.4, relativeTo: .footnote)
    static let labelLarge = AppTextStyle(fontName: FontName.sansSemiBold, size: 14, lineHeight: 20, tracking: 0.1, relativeTo: .callout)
    static let labelMedium = AppTextStyle(fontName: FontName.sansMedium, size: 12, lineHeight: 16, tracking: 0.5, relativeTo: .caption)
    static let labelSmall = AppTextStyle(fontName: FontName.sansMedium, size: 11, lineHeight: 16, tracking: 0.5, relativeTo: .caption2)

    /// The website's split section title (SplitSectionTitle): bold, uppercase, slightly spaced (0.06em).
    static let sectionTitle = AppTextStyle(fontName: FontName.sansSemiBold, size: 18, lineHeight: 24, tracking: 18 * 0.06, relativeTo: .headline)
    /// Small-caps style label used above sections and on the inspiration card (0.14em).
    static let overline = AppTextStyle(fontName: FontName.sansSemiBold, size: 11, lineHeight: 16, tracking: 11 * 0.14, relativeTo: .caption2)
    /// Arabic (verses, hadith) and Urdu titles.
    static let arabic = AppTextStyle(fontName: FontName.arabicRegular, size: 26, lineHeight: 48, tracking: 0, relativeTo: .title)
    /// Readers (blog bodies, fatwa answers) in the serif face.
    static let serifBody = AppTextStyle(fontName: FontName.serifRegular, size: 16, lineHeight: 26, tracking: 0, relativeTo: .body)
    static let serifItalic = AppTextStyle(fontName: FontName.serifItalic, size: 15, lineHeight: 24, tracking: 0, relativeTo: .body)
}

extension View {
    /// Applies a type-scale style: font, letter spacing and line height.
    func textStyle(_ style: AppTextStyle) -> some View {
        font(style.font).tracking(style.tracking).lineSpacing(style.lineSpacing)
    }
}

extension Text {
    /// [textStyle] for a Text that is still concatenated with others.
    func styled(_ style: AppTextStyle) -> Text {
        font(style.font).tracking(style.tracking)
    }
}
