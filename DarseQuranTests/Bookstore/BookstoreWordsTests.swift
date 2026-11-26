import XCTest
@testable import DarseQuran

/// Ported from Android's BookstoreWordsTest.
final class BookstoreWordsTests: XCTestCase {
    func testTheWebsitesBookStatusWords() {
        XCTAssertEqual("Available", bookStatusLabel("AVAILABLE"))
        XCTAssertEqual("Out of Stock", bookStatusLabel("OUT_OF_STOCK"))
        XCTAssertEqual("Coming Soon", bookStatusLabel("COMING_SOON"))
    }

    func testItemsAreCountedAsOnTheWebsite() {
        XCTAssertEqual("1 item", itemCount(1))
        XCTAssertEqual("0 items", itemCount(0))
        XCTAssertEqual("3 items", itemCount(3))
    }

    func testAnUnverifiedEmailBlocksCheckout() {
        XCTAssertEqual(CartCheckout.verifyEmail, cartCheckout(emailVerified: false, selectedCount: 2))
        XCTAssertEqual(CartCheckout.nothingSelected, cartCheckout(emailVerified: true, selectedCount: 0))
        XCTAssertEqual(CartCheckout.ready, cartCheckout(emailVerified: true, selectedCount: 1))
        XCTAssertEqual(CartCheckout.ready, cartCheckout(emailVerified: nil, selectedCount: 1)) // the server decides
    }
}
