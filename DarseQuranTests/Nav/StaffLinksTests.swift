import XCTest
@testable import DarseQuran

/// Ported from Android's ui/nav/StaffLinksTest.kt.
@MainActor
final class StaffLinksTests: XCTestCase {
    private let adminPage = "/admin/students"
    private let shells: [Shell] = [.student, .teacher, .admin, .developer]

    func testAdminLinksOpenOnlyForAdmins() throws {
        let route = try XCTUnwrap(routeForAdminHref(adminPage), "the sample must be a page the app has")
        let expected = HrefDestination.route(.manage(route), underTab: .staff)
        XCTAssertEqual(expected, routeForHref(adminPage, shell: .admin), "opens inside the Admin tab")
        XCTAssertEqual(expected, routeForHref(adminPage, shell: .developer))
        XCTAssertEqual(.tab(.staff), routeForHref("/admin", shell: .admin))
        XCTAssertNil(routeForHref(adminPage, shell: .student))
        XCTAssertNil(routeForHref(adminPage, shell: .teacher))
    }

    func testTeacherLinksOpenTheTeachingTabOnlyForTeachers() {
        XCTAssertEqual(.tab(.staff), routeForHref("/teacher/courses/c1/attendance", shell: .teacher))
        XCTAssertNil(routeForHref("/teacher/courses/c1/attendance", shell: .student))
    }

    func testEveryShellHasThePublicTabsAndStartsOnHome() {
        for shell in shells {
            XCTAssertEqual(.home, Navigator(shell: shell).tab)
            XCTAssertEqual(["Home", "Courses", "Explore"], shell.tabs.prefix(3).map { TabItem.of($0, shell: shell).label })
            XCTAssertEqual("Account", TabItem.of(shell.tabs.last!, shell: shell).label)
        }
        XCTAssertEqual([4, 5, 5, 5], shells.map(\.tabs.count))
        XCTAssertEqual("Teach", TabItem.of(Shell.of("TEACHER").tabs[3], shell: .teacher).label)
        XCTAssertEqual("Admin", TabItem.of(Shell.of("ADMIN").tabs[3], shell: .admin).label)
        XCTAssertEqual("Developer", TabItem.of(Shell.of("DEVELOPER").tabs[3], shell: .developer).label)
        XCTAssertEqual(.student, Shell.of("USER"))
    }

    func testOneRecordsAdminPageOpensItsScreen() {
        XCTAssertEqual(.studentAdmin(id: "s1"), routeForAdminHref("/admin/students/s1"))
        XCTAssertEqual(.receipt(recordId: "r1"), routeForAdminHref("/admin/receipts/r1?from=email"))
        XCTAssertEqual(.bookOrderAdmin(id: "o1"), routeForAdminHref("/admin/bookstore/orders/o1"))
        XCTAssertEqual(.courseHub(portal: .admin, courseId: "c1"), routeForAdminHref("/admin/courses/c1"))
        XCTAssertEqual(.gradeList(portal: .admin, courseId: "c1"), routeForAdminHref("/admin/courses/c1/grades"))
        XCTAssertNil(routeForAdminHref("/admin/students/s1/edit"), "a form page has no screen of its own here")
        XCTAssertNil(routeForAdminHref("/admin/courses/new"))
    }

    func testEverySectionPageHasAScreen() {
        XCTAssertEqual(26, adminHrefRoutes.count)
        XCTAssertEqual(.transactions(expense: false), routeForAdminHref("/admin/transactions/"))
        XCTAssertEqual(.bookOrdersAdmin, routeForAdminHref("/admin/bookstore/orders"))
    }

    func testAnUnknownPortalIsTheTeacherOne() {
        XCTAssertEqual(.admin, Portal.of("admin"))
        XCTAssertEqual(.teacher, Portal.of("teacher"))
        XCTAssertEqual(.teacher, Portal.of("superuser"))
    }
}
