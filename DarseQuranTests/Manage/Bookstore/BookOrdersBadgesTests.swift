import XCTest
@testable import DarseQuran

/// Ported from Android's ui/manage/bookstore/BookOrdersBadgesTest.kt: the tab counts come with each page of the list,
/// in one request (they used to be fetched again with a second list request).
@MainActor
final class BookOrdersBadgesTests: XCTestCase {
    private var server: StubServer!

    override func setUp() async throws {
        server = StubServer()
        server.handler = { _ in .json(#"{"data":[],"totalCount":0,"counts":{"pending":3,"approved":1,"completed":7}}"#) }
    }

    override func tearDown() async throws { CurrentEnvironment.testBaseUrl = nil; server = nil }

    func testTheTabCountsComeWithTheListInOneRequest() async {
        let model = BookOrdersListModel(app: testContainer(server))
        await waitUntil { model.counts != nil && !model.list.state.loading }
        XCTAssertEqual("Pending approvals (3)", bookOrdersTabLabel("Pending approvals", model.counts?.pending))
        XCTAssertEqual("Approved (1)", bookOrdersTabLabel("Approved", model.counts?.approved))
        XCTAssertEqual("Completed (7)", bookOrdersTabLabel("Completed", model.counts?.completed))
        XCTAssertEqual(1, server.requests.count)
        XCTAssertEqual("/api/v1/admin/bookstore/orders", server.requests.first?.path)
    }

    func testATabWithoutOrdersShowsNoCount() {
        XCTAssertEqual("Approved", bookOrdersTabLabel("Approved", 0))
        XCTAssertEqual("Approved", bookOrdersTabLabel("Approved", nil))
    }
}
