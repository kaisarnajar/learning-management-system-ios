import XCTest
@testable import DarseQuran

/// The admin dashboard shows what the website's dashboard shows. Ported from Android's DashboardLayoutTest.kt.
final class DashboardLayoutTests: XCTestCase {
    private let data = DashboardResponse(
        groups: [
            DashboardGroup(
                title: "Payments & Finance",
                links: [
                    DashboardLink(href: "/admin/payments", label: "Pending Payments", count: 3, highlight: true),
                    DashboardLink(href: "/admin/receipts", label: "Payment Receipts", count: 12),
                    // The API sends 0 for finance; the website shows it as a Manage card.
                    DashboardLink(href: "/admin/finance", label: "Finance", count: 0),
                    DashboardLink(href: "/admin/shipping-charges", label: "Shipping charges"),
                ]
            ),
            DashboardGroup(title: "System Settings", links: [DashboardLink(href: "/admin/audit-log", label: "Audit log")]),
        ]
    )

    func testAHighlightedPageIsOnlyUnderActionRequired() {
        XCTAssertEqual(["/admin/payments"], DashboardLayout.actionRequired(data).map(\.href))
        XCTAssertEqual(["/admin/receipts", "/admin/finance"], DashboardLayout.groups(data)[0].links.map(\.href))
    }

    func testToolPagesAreManageCardsAndPagesWithoutACountAreLeftOut() {
        let links = DashboardLayout.groups(data).flatMap(\.links)
        XCTAssertFalse(links.contains { $0.href == "/admin/shipping-charges" })
        XCTAssertTrue(DashboardLayout.isQuickLink(links.first { $0.href == "/admin/finance" }!))
        XCTAssertEqual(["Payments & Finance", "System Settings"], DashboardLayout.groups(data).map(\.title))
    }

    func testTheAnswerDecodesLeniently() throws {
        let json = #"{"groups":[{"title":"People","links":[{"href":"/admin/students","label":"Students","count":5}]}]}"#
        let r = try JSONDecoder().decode(DashboardResponse.self, from: Data(json.utf8))
        XCTAssertEqual(false, r.groups[0].links[0].highlight)
        XCTAssertEqual([], r.actionRequired)
    }
}
