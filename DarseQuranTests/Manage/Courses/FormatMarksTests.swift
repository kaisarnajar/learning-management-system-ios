import XCTest
@testable import DarseQuran

/// Ported from Android's ui/manage/courses/FormatMarksTest.kt (formatMarks is formatCourseMarks here).
final class FormatMarksTests: XCTestCase {
    private let cases: [(Double, String)] = [(12.0, "12"), (12.5, "12.5"), (7.25, "7.25"), (0.0, "0"), (9.999, "10"), (33.333, "33.33"), (100.0, "100")]

    func testFormatsWithoutTrailingZeros() {
        for (marks, text) in cases { XCTAssertEqual(text, formatCourseMarks(marks), "\(marks)") }
    }

    /// Always ASCII digits and a "." (it never reads the phone's language), and the text reads back as the number.
    func testIgnoresThePhonesLanguageAndRoundTrips() {
        for (marks, text) in cases {
            let shown = formatCourseMarks(marks)
            XCTAssertTrue(shown.allSatisfy { $0.isASCII }, shown)
            XCTAssertEqual(Double(text), Double(shown))
        }
    }
}
