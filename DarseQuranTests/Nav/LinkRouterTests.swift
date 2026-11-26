import XCTest
@testable import DarseQuran

/// Ported from Android's ui/nav/LinkRouterTest.kt.
final class LinkRouterTests: XCTestCase {
    private func to(_ href: String) -> HrefDestination? { routeForHref(href, shell: .student) }

    func testPublicPagesOpenTheirScreens() {
        XCTAssertEqual(.route(.blogPost(id: "patience")), to("/blog/patience"))
        XCTAssertEqual(.route(.fatwaDetail(id: "q1")), to("/fatwa/q1#answer"))
        XCTAssertEqual(.route(.announcement(id: "a1")), to("/announcements/a1"))
        XCTAssertEqual(.route(.course(id: "c1")), to("/courses/c1?ref=home"))
        XCTAssertEqual(.route(.libraryItem(id: "l1")), to("/library/l1"))
        XCTAssertEqual(.route(.teacher(id: "t1")), to("/teachers/t1"))
    }

    func testTheAskFormIsNotAFatwaCalledAsk() {
        XCTAssertEqual(.route(.askFatwa), to("/fatwa/ask"))
    }

    func testBookstoreLinksOpenTheBookOrTheOrders() {
        XCTAssertEqual(.route(.book(id: "b1")), to("/bookstore/b1"))
        XCTAssertEqual(.route(.orders), to("/bookstore/orders/o1"))
        XCTAssertEqual(.route(.orders), to("/bookstore/orders"))
        XCTAssertEqual(.route(.bookstore), to("/bookstore"))
    }

    func testTheStudentsOwnPages() {
        XCTAssertEqual(.route(.learn(courseId: "c1", title: "Course")), to("/profile/courses/c1"))
        XCTAssertEqual(.route(.learn(courseId: "c1", title: "Course")), to("/profile/courses/c1/attendance"))
        XCTAssertEqual(.tab(.courses), to("/profile/courses"))
        XCTAssertEqual(.route(.payments), to("/profile/payments"))
        XCTAssertEqual(.route(.orders), to("/profile/cart"))
        XCTAssertEqual(.route(.waivers), to("/profile/waiver-requests"))
        XCTAssertEqual(.route(.reviews), to("/profile/reviews"))
        XCTAssertEqual(.route(.notifications), to("/profile/notifications"))
        XCTAssertEqual(.tab(.account), to("/profile"))
        XCTAssertEqual(.tab(.account), to("/profile/"))
    }

    func testPagesTheAppDoesNotHave() {
        XCTAssertNil(to("/about-us"))
        XCTAssertNil(to("/blog"))
        XCTAssertNil(to("/library"))
        XCTAssertNil(to("/"))
    }
}
