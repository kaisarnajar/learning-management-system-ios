import XCTest
@testable import DarseQuran

/// Ported from Android's HtmlLinksTest.
final class HtmlLinksTests: XCTestCase {
    private let base = "https://darsequranacademy.com"

    func testAcademyLinksStayInTheApp() {
        XCTAssertEqual(.inApp("/blog/patience"), linkTarget("/blog/patience", baseUrl: base))
        XCTAssertEqual(.inApp("/fatwa/q1"), linkTarget("https://darsequranacademy.com/fatwa/q1", baseUrl: base))
        XCTAssertEqual(.inApp("/courses/c1?tab=fees"), linkTarget("https://www.darsequranacademy.com/courses/c1?tab=fees", baseUrl: base))
    }

    func testOtherLinksGoOutside() {
        XCTAssertEqual(.outside("https://sunnah.com/bukhari/1"), linkTarget("https://sunnah.com/bukhari/1", baseUrl: base))
        XCTAssertEqual(.outside("mailto:info@example.test"), linkTarget("mailto:info@example.test", baseUrl: base))
        XCTAssertEqual(.outside("https://cdn.example.test/x"), linkTarget("//cdn.example.test/x", baseUrl: base))
        XCTAssertEqual(.inApp("/blog/x"), linkTarget("//darsequranacademy.com/blog/x", baseUrl: base))
    }

    /// Android checks its Spanned for a click span; here the rendered text carries a link the router keeps in the app.
    @MainActor
    func testLinksCallTheAppAndImagesAreLeftOut() throws {
        let text = try XCTUnwrap(renderHtml(#"<p>Read <a href="/blog/patience">this</a> first.<img src="/uploads/a.png"></p>"#, serif: false))
        let plain = String(text.characters)
        XCTAssertFalse(plain.contains("\u{FFFC}"), "no object-replacement box")
        let links = text.runs.compactMap { run in run.link.map { (String(text[run.range].characters), $0) } }
        XCTAssertEqual(1, links.count)
        XCTAssertEqual("this", links.first?.0)
        XCTAssertEqual(.inApp("/blog/patience"), links.first.map { linkTarget($0.1.absoluteString) })
    }

    func testPreviewsHaveNoImageBoxes() {
        XCTAssertEqual("Hello world", plainText("<p>Hello<img src='x.png'> world</p>"))
    }

    func testPhoneLinksGoToTheirAppAndUnsafeSchemesNowhere() {
        XCTAssertEqual(.web("https://sunnah.com/bukhari/1"), outsideOpen("https://sunnah.com/bukhari/1"))
        XCTAssertEqual(.phoneApp("mailto:info@example.test"), outsideOpen("mailto:info@example.test"))
        XCTAssertEqual(.phoneApp("tel:+911234567890"), outsideOpen("tel:+911234567890"))
        XCTAssertEqual(.ignored, outsideOpen("javascript:alert(1)"))
        XCTAssertEqual(.ignored, outsideOpen("intent://x#Intent;scheme=x;end"))
        XCTAssertEqual(.ignored, outsideOpen("file:///data/data/x"))
    }
}
