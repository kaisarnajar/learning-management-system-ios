import XCTest
@testable import DarseQuran

/// Ported from Android's ReviewRulesTest and WaiverRulesTest.
final class ReviewRulesTests: XCTestCase {
    private let quote = "Twenty characters or more, surely."

    func testTheRatingStartsUnchosenAndMustBeChosen() {
        XCTAssertEqual(0, ReviewDraft().rating)
        XCTAssertEqual(reviewRatingError, reviewErrors(ReviewDraft(quote: quote))[.rating])
        XCTAssertTrue(reviewErrors(ReviewDraft(rating: 5, quote: quote)).isEmpty)
    }

    func testTheReviewNeedsTwentyCharactersAfterTrimming() {
        let errors = reviewErrors(ReviewDraft(rating: 3, quote: "   short but padded         "))
        XCTAssertEqual("Your review must be at least 20 characters.", errors[.quote])
    }

    func testTheLocationStartsAsTheAddressCappedAtTheWebsitesLimit() {
        XCTAssertEqual("Srinagar", newReviewDraft("Srinagar").location)
        XCTAssertEqual(reviewFieldMax, newReviewDraft(String(repeating: "x", count: 200)).location.count)
        XCTAssertEqual("", newReviewDraft(nil).location)
    }

    func testBlankOptionalFieldsAreLeftOut() {
        XCTAssertEqual(
            ReviewRequest(quote: quote, rating: 4, course: nil, location: "Srinagar"),
            reviewRequest(ReviewDraft(rating: 4, quote: "  \(quote) ", course: "  ", location: " Srinagar "))
        )
    }

    func testBadgesReadAsOnTheWebsite() {
        func check(_ r: Review, _ label: String, _ tone: Tone, line: UInt = #line) {
            let (l, t) = reviewStatusLabel(r)
            XCTAssertEqual(label, l, line: line)
            XCTAssertEqual(tone, t, line: line)
        }
        check(Review(id: "r", quote: "q", status: "PENDING"), "Pending approval", .warning)
        check(Review(id: "r", quote: "q", status: "APPROVED"), "Approved", .success)
        check(Review(id: "r", quote: "q", status: "APPROVED", featuredOnHomepage: true), "On homepage", .success)
        check(Review(id: "r", quote: "q", status: "REJECTED"), "Rejected", .danger)
    }

    func testTheMetaLineJoinsCourseAndLocation() {
        XCTAssertEqual("Tajweed · Srinagar", reviewMeta(Review(id: "r", quote: "q", course: "Tajweed", location: "Srinagar")))
        XCTAssertEqual("Srinagar", reviewMeta(Review(id: "r", quote: "q", course: "", location: "Srinagar")))
        XCTAssertNil(reviewMeta(Review(id: "r", quote: "q")))
    }
}

final class WaiverRulesTests: XCTestCase {
    func testTheReasonsAreTheWebsitesInItsOrder() {
        XCTAssertEqual(11, waiverReasons.count)
        XCTAssertEqual("Financial hardship", waiverReasons.first)
        XCTAssertEqual(waiverReasonOther, waiverReasons.last)
    }

    func testOnlyEnrollmentAndCourseFeesAreOfferedWithTheCourseFeeFirstChosen() {
        XCTAssertEqual(["enrollment", "course"], WaiverFee.allCases.map(\.value))
        XCTAssertEqual(.course, defaultWaiverFee)
    }

    func testTheBodyCarriesThePresetAndTheDetailsAsTheWebsiteJoinsThem() {
        XCTAssertEqual(
            WaiverRequestBody(courseId: "c1", feeType: "course", reason: "Financial hardship - Lost my job"),
            waiverRequestBody(courseId: "c1", fee: .course, category: "Financial hardship", details: "  Lost my job ")
        )
        XCTAssertEqual("Student / Currently studying", waiverReason("Student / Currently studying", "   "))
    }

    func testDetailsAreRequiredOnlyForOtherAndACourseMustBeChosen() {
        XCTAssertTrue(waiverFormReady(courseId: "c1", category: "Financial hardship", details: ""))
        XCTAssertFalse(waiverFormReady(courseId: "c1", category: waiverReasonOther, details: " "))
        XCTAssertTrue(waiverFormReady(courseId: "c1", category: waiverReasonOther, details: "My reason"))
        XCTAssertFalse(waiverFormReady(courseId: "", category: "Financial hardship", details: "x"))
    }

    func testOnlyCoursesOpenForEnrollmentAreOfferedByTitle() {
        let courses = [
            Course(id: "1", title: "tajweed", status: "ONGOING"),
            Course(id: "2", title: "Arabic", status: "PUBLISHED"),
            Course(id: "3", title: "Fiqh", status: "COMPLETED"),
            Course(id: "4", title: "Hadith", status: "ON_HOLD"),
            Course(id: "2", title: "Arabic", status: "PUBLISHED"),
        ]
        XCTAssertEqual(["Arabic", "tajweed"], waiverCourseOptions(courses).map(\.title))
    }

    func testFeeTypesReadAsOnTheWebsite() {
        XCTAssertEqual("Enrollment Fee", waiverFeeLabel("ENROLLMENT"))
        XCTAssertEqual("Course Fee", waiverFeeLabel("COURSE"))
        XCTAssertEqual("Both", waiverFeeLabel("BOTH"))
    }

    func testTheAssignedCouponListsEveryIssuedCode() throws {
        let both = try JSONDecoder().decode(WaiverRequest.self, from: Data("""
            {"id":"w","courseId":"c","status":"APPROVED","feeType":"BOTH",
             "coupon":{"id":"x","code":"WAIVE1","percentage":100},"couponCodes":["WAIVE1","WAIVE1-C"]}
            """.utf8))
        XCTAssertEqual("WAIVE1  WAIVE1-C (100% OFF)", waiverCouponText(both))
        let pending = try JSONDecoder().decode(WaiverRequest.self, from: Data(#"{"id":"w","courseId":"c","coupon":null}"#.utf8))
        XCTAssertNil(waiverCouponText(pending))
    }
}
