import XCTest
@testable import DarseQuran

/// Status words and colours as the website shows them. Ported from Android's StatusLabelTest, StatusTonesTest and
/// SplitTitleTest.
final class StatusLabelTests: XCTestCase {
    private func assertLabel(_ expected: (String, Tone), _ actual: (String, Tone), file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(expected.0, actual.0, file: file, line: line)
        XCTAssertEqual(expected.1, actual.1, file: file, line: line)
    }

    func testEnrolmentsReadAsOnTheWebsite() {
        assertLabel(("Active", .info), statusLabel("ACTIVE"))
        assertLabel(("Completed", .success), statusLabel("completed"))
        assertLabel(("Awaiting approval", .warning), statusLabel("PENDING_APPROVAL"))
        assertLabel(("Awaiting enrollment fee", .warning), statusLabel("AWAITING_ENROLLMENT_FEE"))
        assertLabel(("Rejected", .danger), statusLabel("REJECTED"))
    }

    func testADeclinedPaymentIsRejectedButADeclinedOrderIsDeclined() {
        assertLabel(("Pending Verification", .warning), statusLabel("PENDING_VERIFICATION", kind: .payment))
        assertLabel(("Rejected", .danger), statusLabel("DECLINED", kind: .payment))
        assertLabel(("Declined", .danger), statusLabel("DECLINED", kind: .order))
        assertLabel(("Approved", .success), statusLabel("APPROVED", kind: .order))
    }

    func testAPendingWaiverIsUnderReviewAndAPendingReviewAwaitsApproval() {
        assertLabel(("Pending Review", .warning), statusLabel("PENDING", kind: .waiver))
        assertLabel(("Pending approval", .warning), statusLabel("PENDING", kind: .review))
        assertLabel(("Pending", .warning), statusLabel("PENDING"))
    }

    // MARK: StatusTonesTest

    func testAnOrderStatusLooksTheSameWhateverItsCase() {
        XCTAssertEqual(.info, orderStatusTone("SHIPPED"))
        XCTAssertEqual(.info, orderStatusTone("shipped"))
        XCTAssertEqual(.warning, orderStatusTone("PENDING_VERIFICATION"))
        XCTAssertEqual(.success, orderStatusTone("approved"))
        XCTAssertEqual(.danger, orderStatusTone("DECLINED"))
        XCTAssertEqual(.neutral, orderStatusTone("refunded"))
        XCTAssertEqual(.neutral, orderStatusTone(nil))
    }

    func testComingSoonIsAmberEverywhere() {
        XCTAssertEqual(.warning, courseStatusTone("COMING_SOON"))
    }

    // MARK: SplitTitleTest (iOS splits into the plain lead and the accent word instead of a styled string)

    func testTheLastWordIsTheAccentAsOnTheWebsite() {
        let t = splitTitle("Featured courses")
        XCTAssertEqual("FEATURED COURSES", t.lead + t.accent)
        XCTAssertEqual("COURSES", t.accent)
    }

    func testAOneWordTitleIsAllAccent() {
        let t = splitTitle("Announcements")
        XCTAssertEqual("", t.lead)
        XCTAssertEqual("ANNOUNCEMENTS", t.accent)
    }
}
