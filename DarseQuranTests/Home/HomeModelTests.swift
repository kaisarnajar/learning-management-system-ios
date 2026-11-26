import XCTest
@testable import DarseQuran

/// Ported from Android's HomeViewModelTest.
@MainActor
final class HomeModelTests: XCTestCase {
    private final class Backend: @unchecked Sendable {
        let lock = NSLock()
        var resendFails = false
        var homeDelay: TimeInterval = 0
        var homeTitle = "Tajweed"
        var resends = 0
    }

    private var server: SlowStubServer!
    private var backend: Backend!
    private var app: TestApp!
    private var savedFile: URL!

    override func setUp() async throws {
        server = SlowStubServer()
        backend = Backend()
        let backend = backend!
        server.handler = { request in
            switch request.path {
            case "/api/v1/enrollments":
                // The signed-in user's courses answer slowly...
                return (.json(#"{"data":[{"id":"e1","courseId":"c1","status":"active"}]}"#), 0.8)
            case "/api/v1/home":
                let (delay, title) = backend.lock.withLock { (backend.homeDelay, backend.homeTitle) }
                return (.json(#"{"success":true,"courses":[{"id":"c1","title":"\#(title)"}]}"#), delay)
            case "/api/v1/auth/resend-verification":
                let fails = backend.lock.withLock { backend.resends += 1; return backend.resendFails }
                return (fails ? .json(#"{"error":"Too many requests."}"#, status: 429) : .json(#"{"success":true}"#), 0)
            default:
                return (.json("{}", status: 404), 0)
            }
        }
        CurrentEnvironment.testBaseUrl = server.baseUrl
        savedFile = FileManager.default.temporaryDirectory.appendingPathComponent("home-\(UUID().uuidString).json")
        app = TestApp(server, savedHome: SavedHome(file: savedFile))
        app.signIn()
    }

    override func tearDown() async throws {
        app.sessionStore.clear()
        CurrentEnvironment.testBaseUrl = nil
        try? FileManager.default.removeItem(at: savedFile)
        server = nil
    }

    private func model() -> HomeModel { HomeModel(repo: app.repo, auth: app.auth) }

    func testASlowLoadForThePreviousUserDoesNotOverwriteTheSignedOutHome() async throws {
        let vm = model()
        await waitUntil { !self.server.requests.isEmpty } // the signed-in load is under way
        app.sessionStore.clear()                         // ...and the user signs out
        await waitUntil { vm.session == nil && !vm.loading }
        try await Task.sleep(for: .milliseconds(1200))   // long after the slow answer arrived
        XCTAssertEqual(vm.enrollments, [])
    }

    func testATokenRefreshForTheSameUserDoesNotReload() async throws {
        let vm = model()
        await waitUntil { !vm.enrollments.isEmpty } // the whole load, slowest call included
        let before = server.requests.count
        app.signIn(access: "a2", refresh: "r2")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(server.requests.count, before)
        XCTAssertEqual(vm.session?.accessToken, "a2") // the new session still reaches the screen
    }

    func testResendingTheVerificationEmailSaysItWasSentAndSendsOnce() async throws {
        let vm = model()
        vm.resendVerification()
        vm.resendVerification() // a second tap while sending
        await waitUntil { vm.resend.sent }
        let sent = vm.resend
        vm.resendVerification() // and after it was sent
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(homeResendLabel(sent), "Sent")
        XCTAssertEqual(sent.message, homeVerificationSent)
        XCTAssertEqual(backend.lock.withLock { backend.resends }, 1)
    }

    func testAFailedResendShowsTheServersErrorAndCanBeTriedAgain() async {
        backend.lock.withLock { backend.resendFails = true }
        let vm = model()
        vm.resendVerification()
        await waitUntil { vm.resend.message != nil }
        let failed = vm.resend
        XCTAssertFalse(failed.sent)
        XCTAssertEqual(homeResendLabel(failed), "Resend Verification Email")
        XCTAssertFalse(failed.message?.trimmed.isEmpty ?? true)
    }

    func testResendWordingFollowsTheWebsite() {
        XCTAssertEqual(homeResendOutcome(ApiResult<OkResponse>.failure(ApiError(message: ""))).message, "Failed to resend verification email.")
        XCTAssertEqual(homeResendOutcome(ApiResult<OkResponse>.failure(ApiError(message: "Too many requests."))).message, "Too many requests.")
    }

    func testTheHomeContentShowsWithoutWaitingForTheStudentsSlowerCalls() async {
        let vm = model()
        await waitUntil { !(vm.content?.courses.isEmpty ?? true) }
        XCTAssertEqual(vm.enrollments, []) // the enrollments (800 ms) are still on the way
        await waitUntil { !vm.enrollments.isEmpty }
    }

    func testAColdStartShowsTheSavedHomeUntilTheNewOneArrives() async {
        let saved = SavedHome(file: savedFile)
        saved.write(HomeResponse(courses: [Course(id: "c0", title: "Saved")]))
        backend.lock.withLock { backend.homeDelay = 1.5; backend.homeTitle = "Fresh" }
        let vm = model()
        await waitUntil(1) { vm.content?.courses.first?.title == "Saved" }
        await waitUntil { vm.content?.courses.first?.title == "Fresh" }
        XCTAssertEqual(saved.read()?.courses.first?.title, "Fresh") // and the new one is saved for next time
    }

    // The cards (the rules inside Android's loadNow).

    func testActionCardsForAnUnverifiedIncompleteStudentWithFeesDue() {
        let today = YearMonth(year: 2026, month: 11)
        let course = Course(id: "c1", title: "Tajweed", priceInrPaise: 50000, monthlyFeeInrPaise: 34900)
        let me = Profile(id: "u1", email: "s@example.test", emailVerified: nil, profileComplete: false)
        let actions = homeActions(
            profile: me,
            enrollments: [
                Enrollment(id: "e1", courseId: "c1", status: "awaiting_enrollment_fee", course: course),
                Enrollment(id: "e2", courseId: "c2", status: "active", course: Course(id: "c2", title: "Nazira", monthlyFeeInrPaise: 34900)),
            ],
            submissions: [],
            today: today
        )
        XCTAssertEqual(actions.map(\.kind), [.verifyEmail, .completeProfile, .payEnrollment, .payCourseFee])
        XCTAssertEqual(actions[2].message, "Tajweed · ₹500")
        XCTAssertEqual(actions[3].title, "November 2026 fee is due")
        XCTAssertEqual(actions[3].message, "Nazira · ₹349")
    }

    func testAPaymentUnderReviewHidesItsPayCardAndSaysSo() {
        let course = Course(id: "c1", title: "Tajweed", priceInrPaise: 50000)
        let pending = PaymentSubmission(id: "p1", courseId: "c1", paymentType: "enrollment", status: "pending_verification")
        let actions = homeActions(
            profile: nil,
            enrollments: [Enrollment(id: "e1", courseId: "c1", status: "awaiting_enrollment_fee", course: course)],
            submissions: [pending]
        )
        XCTAssertEqual(actions.map(\.kind), [.underReview])
        XCTAssertEqual(actions[0].message, "The academy will confirm it shortly.")
        let two = homeActions(profile: nil, enrollments: [], submissions: [pending, PaymentSubmission(id: "p2", status: "pending_verification")])
        XCTAssertEqual(two[0].message, "2 payments are being verified.")
    }
}
