import Observation
import SwiftUI

/// The tabs a signed-in user sees. As on the website, everyone gets the public app (Home, Courses, Explore, Account);
/// staff also get one entry into their area, named as in the website's header: Teach, Admin or Developer.
enum Shell: String, Sendable {
    case student, teacher, admin, developer

    static func of(_ role: String?) -> Shell {
        switch role {
        case Roles.admin: .admin
        case Roles.developer: .developer
        case Roles.teacher: .teacher
        default: .student
        }
    }

    var tabs: [AppTab] { self == .student ? [.home, .courses, .explore, .account] : [.home, .courses, .explore, .staff, .account] }

    /// Admins and developers share the admin panel.
    var adminPanel: Bool { self == .admin || self == .developer }

    /// The staff tab's label.
    var staffLabel: String {
        switch self {
        case .teacher: "Teach"
        case .admin: "Admin"
        case .developer: "Developer"
        case .student: ""
        }
    }
}

/// Where the user is: the selected tab and each tab's stack of screens (Android's NavHostController). Screens reach it
/// through `@Environment(Navigator.self)`.
@MainActor
@Observable
final class Navigator {
    let shell: Shell
    var tab: AppTab = .home
    var paths: [AppTab: [Route]] = [:]
    /// Checks whether someone is signed in (so screens that need an account open sign-in first).
    @ObservationIgnored var isSignedIn: () -> Bool = { false }
    @ObservationIgnored var toast: (String) -> Void = { _ in }

    init(shell: Shell) { self.shell = shell }

    func path(_ tab: AppTab) -> Binding<[Route]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }

    var currentPath: [Route] { paths[tab] ?? [] }

    /// The bottom bar shows only on a tab's first screen (detail screens get the full height).
    var showsTabBar: Bool { currentPath.isEmpty }

    /// Opens [route] on top of the current tab.
    func push(_ route: Route) {
        if case .manage = route, shell == .student { return } // staff screens don't exist in a student's app
        paths[tab, default: []].append(route)
    }

    /// Back.
    func pop() {
        guard !(paths[tab] ?? []).isEmpty else { return }
        paths[tab]?.removeLast()
    }

    /// Switches tab, keeping each tab's stack (Android's switchTab with saveState/restoreState).
    func switchTab(_ newTab: AppTab) {
        if tab == newTab { paths[newTab] = [] } else { tab = newTab }
    }

    /// Back to the first screen of the current tab.
    func popToRoot() { paths[tab] = [] }

    /// Replaces the screens from the last [route] onwards (Checkout → Orders replaces the cart and the finished checkout).
    func replace(upTo route: Route, inclusive: Bool = true, with newRoute: Route) {
        var stack = paths[tab] ?? []
        if let index = stack.lastIndex(of: route) { stack.removeSubrange((inclusive ? index : index + 1)...) }
        stack.append(newRoute)
        paths[tab] = stack
    }

    /// Opens [route] when signed in, otherwise sign-in first.
    func signedIn(_ route: Route) { push(isSignedIn() ? route : .signIn) }

    /// Website links (notifications, article links) → app screens; false when the app has no screen for it.
    @discardableResult
    func openHref(_ href: String) -> Bool {
        guard let destination = routeForHref(href, shell: shell) else { return false }
        switch destination {
        case .tab(let t):
            switchTab(t)
        case .route(let r, let underTab):
            // Staff pages open inside the staff tab, so Back leads to the staff area, not to wherever the link was.
            if let underTab { tab = underTab }
            push(r)
        }
        return true
    }

    /// Links inside articles, fatwas and announcements: academy pages open here, anything else in the browser.
    func openLink(_ href: String) {
        switch linkTarget(href) {
        case .inApp(let path): if !openHref(path) { openWeb(path) }
        case .outside(let url): openOutside(url)
        }
    }
}
