import Foundation

/// Where a website link leads in the app: a tab to switch to, or a screen to open (on top of [underTab] when given;
/// staff pages open inside the staff tab). Android's HrefDestination.
enum HrefDestination: Equatable {
    case tab(AppTab)
    case route(Route, underTab: AppTab? = nil)
}

/// The app's screen for a path of the academy's website (from a notification or a link in an article), for a user in
/// [shell]; nil when the app has no screen for it. Staff pages only lead somewhere for staff: admin pages for admins,
/// the teaching tab for teachers. Android's routeForHref.
func routeForHref(_ href: String, shell: Shell) -> HrefDestination? {
    let path = href.components(separatedBy: "#")[0].components(separatedBy: "?")[0]
    let parts = path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
    switch parts.first {
    case "admin":
        guard shell.adminPanel else { return nil }
        if parts.count == 1 { return .tab(.staff) }
        return routeForAdminHref(path).map { .route(.manage($0), underTab: .staff) }
    case "teacher":
        return shell == .teacher ? .tab(.staff) : nil
    case "profile":
        return routeForProfileHref(Array(parts.dropFirst()))
    default:
        return routeForPublicHref(parts).map { .route($0) }
    }
}

/// The website's public pages that have a screen in the app; "/fatwa/ask" is the form, not a fatwa called "ask".
private func routeForPublicHref(_ parts: [String]) -> Route? {
    guard parts.count > 1 else { return parts == ["bookstore"] ? .bookstore : nil }
    let id = parts[1]
    switch parts[0] {
    case "blog": return .blogPost(id: id)
    case "fatwa": return id == "ask" ? .askFatwa : .fatwaDetail(id: id)
    case "announcements": return .announcement(id: id)
    case "courses": return .course(id: id)
    case "library": return .libraryItem(id: id)
    case "teachers": return .teacher(id: id)
    case "bookstore": return id == "orders" ? .orders : .book(id: id)
    default: return nil
    }
}

/// The student's own pages ("/profile/..."); the profile itself is the Account tab.
private func routeForProfileHref(_ rest: [String]) -> HrefDestination {
    switch rest.first {
    case "courses":
        if rest.count > 1 { return .route(.learn(courseId: rest[1], title: "Course")) }
        return .tab(.courses)
    case "payments": return .route(.payments)
    case "cart": return .route(.orders)
    case "waiver-requests": return .route(.waivers)
    case "reviews": return .route(.reviews)
    case "notifications": return .route(.notifications)
    default: return .tab(.account)
    }
}

/// A link opened from outside the app (darsequran://blog/abc, or a universal link to the academy's site later): the
/// website path it stands for.
func pathForIncomingURL(_ url: URL) -> String? {
    if url.scheme == "darsequran" {
        // darsequran://blog/abc → /blog/abc (the host is the first segment).
        let host = url.host.map { "/" + $0 } ?? ""
        return host + url.path
    }
    if url.scheme == "https" || url.scheme == "http" { return url.path }
    return nil
}
