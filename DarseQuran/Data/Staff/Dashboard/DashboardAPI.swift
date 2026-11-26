import Foundation

// The admin dashboard (/api/v1/admin/dashboard), ported from Android's data/staff/dashboard/DashboardApi.kt.

struct DashboardLink: Model {
    var href: String
    var label: String
    var count: Int? = nil
    @Default<False> var highlight: Bool = false
}

struct DashboardGroup: Model {
    var title: String
    @Default<Empty.List<DashboardLink>> var links: [DashboardLink] = []
}

struct DashboardResponse: Model {
    @Default<Empty.List<DashboardGroup>> var groups: [DashboardGroup] = []
    @Default<Empty.List<DashboardLink>> var actionRequired: [DashboardLink] = []
}

/// The website's admin dashboard rules (app/admin/page.tsx): tool pages in [quickLinkHrefs] are "Manage" cards with no
/// number; other pages show their count, and a highlighted one only under Action Required, not in its group too. A page
/// with neither a count nor a place among the tool pages is not on the dashboard.
enum DashboardLayout {
    /// The website's ADMIN_DASHBOARD_LINK_HREFS.
    static let quickLinkHrefs: Set<String> = [
        "/admin/payment-settings", "/admin/finance", "/admin/transactions",
        "/admin/coupons/finance", "/admin/audit-log",
    ]

    static func isQuickLink(_ link: DashboardLink) -> Bool { quickLinkHrefs.contains(link.href) }

    static func actionRequired(_ data: DashboardResponse) -> [DashboardLink] {
        data.groups.flatMap(\.links).filter { !isQuickLink($0) && $0.count != nil && $0.highlight }
    }

    /// Each group with the cards it shows; groups left empty are dropped.
    static func groups(_ data: DashboardResponse) -> [DashboardGroup] {
        data.groups
            .map { group in
                var g = group
                g.links = g.links.filter { isQuickLink($0) || ($0.count != nil && !$0.highlight) }
                return g
            }
            .filter { !$0.links.isEmpty }
    }
}

struct DashboardAPI: StaffService {
    let client: APIClient

    func dashboard() async throws -> DashboardResponse { try await client.get("admin/dashboard") }
}
