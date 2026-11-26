import SwiftUI

/// Shapes and spacing from DESIGN.md and Theme.kt (AcademyShapes): a 4pt grid, 20pt screen padding, 16pt card padding.
enum Radius {
    /// extraSmall
    static let xs: CGFloat = 6
    /// Inputs and full-width buttons (small / medium).
    static let input: CGFloat = 8
    /// Cards (large).
    static let card: CGFloat = 12
    /// Sheets and dialogs (extraLarge).
    static let sheet: CGFloat = 16
}

enum Spacing {
    static let grid: CGFloat = 4
    static let screen: CGFloat = 20
    static let card: CGFloat = 16
}

/// Light / dark / system, as Android's theme setting ("system", "light" or "dark").
enum AppearanceSetting: String, CaseIterable, Sendable {
    case system, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var label: String {
        switch self {
        case .system: "System default"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}
