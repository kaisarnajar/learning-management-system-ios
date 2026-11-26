import XCTest
@testable import DarseQuran

/// Ported from Android's FormatTest.
final class FormatTests: XCTestCase {
    private func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    func testOneDayIsSingular() {
        XCTAssertEqual("1 day ago", relativeTime(iso(Date().addingTimeInterval(-30 * 3600))))
    }

    func testMoreDaysArePlural() {
        XCTAssertEqual("3 days ago", relativeTime(iso(Date().addingTimeInterval(-(3 * 86_400 + 60)))))
    }

    func testAZonelessDateTimeKeepsItsTime() {
        XCTAssertEqual("16 Nov 2026, 10:00 AM", formatDateTime("2026-11-16T10:00:00"))
    }

    func testAUtcInstantIsShownInAcademyTime() {
        XCTAssertEqual("16 Nov 2026, 3:30 PM", formatDateTime("2026-11-16T10:00:00Z"))
    }

    func testCalendarDates() {
        XCTAssertEqual("16 Nov 2026", formatCalendarDate("2026-11-16T00:00:00.000Z"))
        XCTAssertEqual("", formatCalendarDate(nil))
        XCTAssertEqual("To be announced", formatCalendarDate("To be announced"))
    }

    func testRupeesWithAndWithoutPaise() {
        XCTAssertEqual("₹349", rupees(34_900))
        XCTAssertEqual("₹123.50", rupees(12_350))
        // Android's JVM test can't check the Indian grouping (it comes from Android's ICU); iOS has ICU, so check it here.
        XCTAssertEqual("₹1,00,000", rupees(10_000_000))
        XCTAssertEqual("-₹15,84,753.50", formatInr(-158_475_350))
    }

    func testOneFormatterForAllAmounts() {
        XCTAssertEqual("₹0", formatInr(0))
        XCTAssertEqual("₹0.01", formatInr(1))
        XCTAssertEqual("₹0.99", formatInr(99))
        XCTAssertEqual("₹1", formatInr(100))
        XCTAssertEqual("₹10.50", formatInr(1050))
        XCTAssertEqual("-₹10.50", formatInr(-1050))
        XCTAssertEqual("₹50.00", formatInr(5000, exact: true))
        XCTAssertEqual("₹10.50", formatInr(1050, exact: true))
    }

    func testHugeTotalsKeepTheirPaise() {
        // A Double can't hold every paise of a very large Int64; Decimal can.
        XCTAssertEqual("₹92233720368547758.07", formatInr(Int64.max).replacingOccurrences(of: ",", with: ""))
    }
}
