import XCTest
@testable import DarseQuran

/// Ported from Android's CourseWordsTest.
final class CourseWordsTests: XCTestCase {
    private func enrollment(_ status: String, fee: Int = 0, completedAt: String? = nil, rejectedAt: String? = nil) -> Enrollment {
        Enrollment(
            id: "e1", courseId: "c1", status: status, createdAt: "2026-03-02T10:00:00.000Z",
            completedAt: completedAt, rejectedAt: rejectedAt,
            course: Course(id: "c1", title: "Tajweed", monthlyFeeInrPaise: fee)
        )
    }

    func testRollNumbersArePaddedAsOnTheWebsite() {
        XCTAssertEqual("Roll No: 05", rollNumberLabel(5))
        XCTAssertEqual("Roll No: 123", rollNumberLabel(123))
    }

    func testARejectedRequestSaysWhenAndWhenItWasMade() {
        XCTAssertEqual(
            [
                "This request was not approved on 10 Mar 2026. Contact the academy if you have questions.",
                "Requested 2 Mar 2026",
            ],
            enrollmentNotes(enrollment("rejected", rejectedAt: "2026-03-10T08:00:00.000Z"))
        )
        XCTAssertEqual(
            "This request was not approved. Contact the academy if you have questions.",
            enrollmentNotes(enrollment("rejected")).first
        )
    }

    func testTheOtherStatuses() {
        XCTAssertEqual(["No fee required"], enrollmentNotes(enrollment("active")))
        XCTAssertEqual([], enrollmentNotes(enrollment("active", fee: 50000)))
        XCTAssertEqual(["Awaiting enrollment approval by the academy."], enrollmentNotes(enrollment("pending_approval")))
        XCTAssertEqual(["Completed 1 Jun 2026"], enrollmentNotes(enrollment("completed", completedAt: "2026-06-01T08:00:00.000Z")))
    }

    func testUngradedExamsAreLeftOutOfTheReport() {
        let grades = [
            GradeEntry(id: "g1", title: "Midterm", maxMarks: 50, marksObtained: 40),
            GradeEntry(id: "g2", title: "Oral", maxMarks: 20, marksObtained: 0),
            GradeEntry(id: "g3", title: "Final", maxMarks: 100, marksObtained: nil),
        ]
        XCTAssertEqual(StudentGradeSummary(exams: 2, obtained: 40, max: 70, percentage: 57), gradeSummary(grades))
        XCTAssertEqual("—", gradeMarks(grades[2]).marks)
        XCTAssertNil(gradeMarks(grades[2]).note)
        XCTAssertEqual("0 / 20", gradeMarks(grades[1]).marks)
        XCTAssertEqual("recorded as 0", gradeMarks(grades[1]).note)
        XCTAssertEqual("40 / 50", gradeMarks(grades[0]).marks)
        XCTAssertNil(gradeMarks(grades[0]).note)
    }
}
