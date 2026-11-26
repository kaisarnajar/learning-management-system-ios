import XCTest
@testable import DarseQuran

/// The `answerProblem` part of Android's ui/manage/common/FeaturedSwitchTest.kt, and the editor HTML the website keeps
/// (WebsiteHtml.kt).
final class FatwaAnswerTests: XCTestCase {
    func testFatwaAnswersNeedTwentyVisibleCharacters() {
        XCTAssertEqual("Write the answer first.", answerProblem("<p>&nbsp;</p>"))
        XCTAssertEqual("The answer must be at least 20 characters.", answerProblem("<p><b>Yes.</b></p>"))
        XCTAssertNil(answerProblem("<p>Yes, it is permissible in this case.</p>"))
    }

    func testStyledSpansBecomeTagsTheWebsiteKeeps() {
        XCTAssertEqual(
            "<p><strong><em>Bold italic</em></strong> and <u>under</u></p>",
            toWebsiteHtml(#"<p><span style="font-weight: bold; font-style: italic;">Bold italic</span> and <span style="text-decoration: underline">under</span></p>"#)
        )
        XCTAssertEqual(
            "<h2 style=\"text-align: center\">Title</h2>",
            toWebsiteHtml(#"<p style="text-align: center"><span style="font-size: 22px">Title</span></p>"#)
        )
        XCTAssertEqual("<p>a <s>b</s></p>", toWebsiteHtml("<p>a <strike>b</strike></p>"))
        XCTAssertTrue(isBlankHtml("<p></p>"))
    }
}
