import XCTest
@testable import DarseQuran

/// Ported from Android's data/remote/StatusesTest.
final class StatusesTests: XCTestCase {
    func testOnlyStudyingOrFinishedStudentsOpenTheCourse() {
        XCTAssertTrue(EnrollmentStatus.opensLearn("active"))
        XCTAssertTrue(EnrollmentStatus.opensLearn("completed"))
        XCTAssertFalse(EnrollmentStatus.opensLearn("awaiting_enrollment_fee"))
        XCTAssertFalse(EnrollmentStatus.opensLearn("pending_approval"))
    }

    func testAdminsAndDevelopersUseTheAdminArea() {
        XCTAssertTrue(Roles.isAdmin("ADMIN")); XCTAssertTrue(Roles.isAdmin("DEVELOPER"))
        XCTAssertFalse(Roles.isAdmin("TEACHER")); XCTAssertFalse(Roles.isAdmin(nil))
    }

    func testFeeText() {
        XCTAssertEqual("Free", courseFeeText(Course(id: "c1", title: "Tajweed")))
        XCTAssertEqual("₹500 / month", courseFeeText(Course(id: "c1", title: "Tajweed", monthlyFeeInrPaise: 50_000)))
        XCTAssertEqual("₹2,000 one time", courseFeeText(Course(id: "c1", title: "Tajweed", monthlyFeeInrPaise: 200_000, feeFrequency: "ONE_TIME")))
    }
}
