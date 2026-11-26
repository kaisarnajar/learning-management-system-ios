import XCTest
@testable import DarseQuran

/// Format.swift's month and fee helpers. Ported from Android's ui/common FeesTest and AcademyTodayTest.
final class FeesTests: XCTestCase {
    private let today = YearMonth(year: 2026, month: 11)
    private let active = Enrollment(id: "e1", courseId: "c1", status: "active", course: Course(id: "c1", title: "Tajweed", monthlyFeeInrPaise: 50000))
    private func paid(_ label: String, _ status: String = "approved") -> PaymentSubmission {
        PaymentSubmission(id: "p1", courseId: "c1", paymentType: "monthly", label: label, status: status)
    }

    func testTheLabelMatchesTheWebsites() { XCTAssertEqual("Monthly fee — November 2026", monthlyFeeLabel(today)) }

    func testDueWithNoPaymentForTheMonth() { XCTAssertTrue(monthlyFeeDue(active, [], today: today)) }
    func testNotDueOncePaid() { XCTAssertFalse(monthlyFeeDue(active, [paid("Monthly fee — November 2026")], today: today)) }
    func testNotDueWhileUnderReview() {
        XCTAssertFalse(monthlyFeeDue(active, [paid("Monthly fee — November 2026", "pending_verification")], today: today))
    }
    func testDueAgainWhenRefused() { XCTAssertTrue(monthlyFeeDue(active, [paid("Monthly fee — November 2026", "rejected")], today: today)) }
    func testLastMonthsPaymentDoesNotCount() { XCTAssertTrue(monthlyFeeDue(active, [paid("Monthly fee — October 2026")], today: today)) }
    func testAYearlyFeeStartingThisMonthIsNotThisMonthsFee() {
        XCTAssertTrue(monthlyFeeDue(active, [paid("Yearly fee — starting November 2026")], today: today))
    }
    func testOlderLabelsStillCount() { XCTAssertFalse(monthlyFeeDue(active, [paid("November 2026")], today: today)) }

    func testOnlyForActiveMonthlyCourses() {
        var completed = active
        completed.status = "completed"
        XCTAssertFalse(monthlyFeeDue(completed, [], today: today))
        var yearly = active
        yearly.course?.feeFrequency = "YEARLY"
        XCTAssertFalse(monthlyFeeDue(yearly, [], today: today))
    }

    // AcademyTodayTest

    private func instant(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func testUsesTheAcademysDateNotThePhones() {
        // 20:00 UTC on 24 Nov is already 01:30 on 25 Nov in India; a phone set to New York still says 24 Nov (15:00).
        let t = academyToday(now: instant("2026-11-24T20:00:00Z"))
        XCTAssertEqual([2026, 11, 25], [t.year, t.month, t.day])
        XCTAssertEqual(YearMonth(year: 2026, month: 11), YearMonth.current(now: instant("2026-11-30T20:00:00Z")).plusMonths(-1))
    }

    func testSameDayWhenBothAgree() {
        let t = academyToday(now: instant("2026-11-24T06:00:00Z"))
        XCTAssertEqual([2026, 11, 24], [t.year, t.month, t.day])
    }
}
