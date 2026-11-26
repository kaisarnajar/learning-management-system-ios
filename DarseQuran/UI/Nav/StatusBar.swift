import ObjectiveC
import SwiftUI
import UIKit

/// The status bar's text colour (Android's HeroUnderStatusBar): light while a screen's dark green hero sits under it,
/// otherwise the system's (dark text in light mode, light in dark mode).
///
/// SwiftUI has no per-screen status bar style while the navigation bar is hidden, so the window's root hosting
/// controller is taught to ask [StatusBar.light]: its class's `preferredStatusBarStyle` is replaced once at launch.
@MainActor
enum StatusBar {
    nonisolated(unsafe) private static var lightContent = false
    private static var installed = false

    static var light: Bool {
        get { lightContent }
        set {
            guard newValue != lightContent else { return }
            lightContent = newValue
            install()
            root?.setNeedsStatusBarAppearanceUpdate()
        }
    }

    private static var root: UIViewController? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.keyWindow?.rootViewController
    }

    private static func install() {
        guard !installed, let root else { return }
        let cls: AnyClass = type(of: root)
        let selector = #selector(getter: UIViewController.preferredStatusBarStyle)
        guard let method = class_getInstanceMethod(cls, selector) else { return }
        let block: @convention(block) (UIViewController) -> UIStatusBarStyle = { _ in lightContent ? .lightContent : .default }
        class_replaceMethod(cls, selector, imp_implementationWithBlock(block), method_getTypeEncoding(method))
        installed = true
    }
}

extension Navigator {
    /// Whether the screen on show has its dark hero under the status bar: Home, Account and the Admin dashboard,
    /// the course page and the sign-in screens (the Android screens that call HeroUnderStatusBar).
    var heroUnderStatusBar: Bool {
        guard let top = currentPath.last else {
            switch tab {
            case .home, .account: return true
            case .staff: return shell.adminPanel
            case .courses, .explore: return false
            }
        }
        switch top {
        case .course, .signIn, .register, .forgotPassword: return true
        default: return false
        }
    }
}
