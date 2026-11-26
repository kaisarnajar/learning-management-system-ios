import XCTest
@testable import DarseQuran

/// The enrol button follows the website's CourseEnrollButton, state by state (Android's EnrollButtonTest).
final class EnrollButtonTests: XCTestCase {
    private func detail(_ status: String? = nil, feePending: Bool = false, open: Bool = true) -> CourseDetailResponse {
        CourseDetailResponse(
            course: Course(id: "c1", title: "Tajweed", priceInrPaise: 50_000),
            enrollmentOpen: open,
            enrollment: status.map { CourseEnrollmentState(id: "e1", status: $0, enrollmentFeePending: feePending) }
        )
    }

    private func label(_ d: CourseDetailResponse, _ gate: EnrollGate = .ready) -> String { enrollButton(d, gate: gate, actions: .none).label }

    private func profile(complete: Bool, verified: Bool) -> Profile {
        Profile(id: "u1", email: "a@example.test", emailVerified: verified ? "2026-01-01" : nil, profileComplete: complete)
    }

    func testBeforeRequestingTheChecksComeInTheWebsitesOrder() {
        XCTAssertEqual(.signIn, enrollGate(signedIn: false, profile: nil))
        XCTAssertEqual(.completeProfile, enrollGate(signedIn: true, profile: profile(complete: false, verified: false)))
        XCTAssertEqual(.verifyEmail, enrollGate(signedIn: true, profile: profile(complete: true, verified: false)))
        XCTAssertEqual(.ready, enrollGate(signedIn: true, profile: profile(complete: true, verified: true)))
        XCTAssertEqual("Sign in to request enrollment", label(detail(), .signIn))
        XCTAssertEqual("Complete profile to enroll", label(detail(), .completeProfile))
        XCTAssertEqual("Verify your email to enroll", label(detail(), .verifyEmail))
        XCTAssertEqual("Request enrollment", label(detail()))
    }

    func testAnExistingEnrollmentDecidesTheButton() {
        XCTAssertEqual("Awaiting enrollment approval", label(detail("pending_approval")))
        XCTAssertEqual("Pay enrollment fee · ₹500", label(detail("awaiting_enrollment_fee")))
        XCTAssertEqual("Awaiting payment verification", label(detail("awaiting_enrollment_fee", feePending: true)))
        XCTAssertEqual("Enrolled — Open course", label(detail("active")))
        XCTAssertEqual("Completed — Open course", label(detail("completed")))
    }

    func testARejectedRequestMayBeMadeAgain() { XCTAssertEqual("Request enrollment", label(detail("rejected"))) }

    func testAClosedCourseSaysWhy() {
        XCTAssertEqual("Not accepting students", label(detail(open: false)))
        XCTAssertEqual("Enrollment has not started yet. Coming soon!", enrollmentClosedMessage("COMING_SOON"))
    }

    func testOnlyAnActionableButtonIsEnabled() {
        XCTAssertFalse(enrollButton(detail("pending_approval"), gate: .ready, actions: .none).enabled)
        XCTAssertTrue(enrollButton(detail("awaiting_enrollment_fee"), gate: .ready, actions: .none).enabled)
    }
}

/// Ported from Android's PayCourseFeeTest.
final class PayCourseFeeTests: XCTestCase {
    private func enrollment(status: String = "active", fee: Int = 50000, frequency: String? = "MONTHLY") -> Enrollment {
        Enrollment(id: "e1", courseId: "c1", status: status, course: Course(id: "c1", title: "Tajweed", monthlyFeeInrPaise: fee, feeFrequency: frequency))
    }

    private func courseFee(_ status: String) -> PaymentSubmission {
        PaymentSubmission(id: "p1", courseId: "c1", paymentType: "monthly", status: status)
    }

    func testAnActiveCourseWithAMonthlyFeeCanBePaid() { XCTAssertTrue(canPayCourseFee(enrollment(), [])) }
    func testAFinishedCourseCannot() { XCTAssertFalse(canPayCourseFee(enrollment(status: "completed"), [])) }
    func testAFreeCourseCannot() { XCTAssertFalse(canPayCourseFee(enrollment(fee: 0), [])) }
    func testAnUnknownEnrollmentCannot() { XCTAssertFalse(canPayCourseFee(nil, [])) }

    func testAOneTimeFeeOnlyUntilItIsPaid() {
        let once = enrollment(frequency: "ONE_TIME")
        XCTAssertTrue(canPayCourseFee(once, []))
        XCTAssertFalse(canPayCourseFee(once, [courseFee("pending_verification")]))
        XCTAssertFalse(canPayCourseFee(once, [courseFee("approved")]))
        XCTAssertTrue(canPayCourseFee(once, [courseFee("rejected")]))
    }
}
