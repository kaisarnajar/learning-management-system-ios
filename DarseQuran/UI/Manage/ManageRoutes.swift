import SwiftUI

/// The staff screens (teacher, admin and developer), opened as `Route.manage(...)`. Android's ManageRoutes and the
/// section route files under ui/manage and ui/teach.
enum ManageRoute: Hashable, Sendable {
    case placeholder
}

/// The app screen for a website admin path (a section, or one record's page), or nil when the app has none.
func routeForAdminHref(_ href: String) -> ManageRoute? { nil }

/// The screen for a staff route.
struct ManageDestination: View {
    let route: ManageRoute
    var body: some View { StubScreen(title: "Admin") }
}
