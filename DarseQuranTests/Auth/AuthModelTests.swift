import XCTest
@testable import DarseQuran

/// Ported from Android's AuthViewModelTest.
@MainActor
final class AuthModelTests: XCTestCase {
    private let tokens = #"{"accessToken":"a","refreshToken":"r","user":{"id":"u1","email":"student@example.test"}}"#
    private var server: StubServer!
    private var container: AppContainer!

    override func setUp() async throws {
        server = StubServer()
        container = testContainer(server)
    }

    override func tearDown() async throws {
        GoogleWelcome.disarm()
        container.sessionStore.clear()
        CurrentEnvironment.testBaseUrl = nil
        container = nil
        server = nil
    }

    private func answer(_ response: StubServer.Response) { server.handler = { _ in response } }

    private func model() -> AuthModel { AuthModel(auth: container.auth) }

    private func settled(_ model: AuthModel) async -> AuthState {
        await waitUntil(5, "done or error") { model.state.done || model.state.error != nil }
        return model.state
    }

    func testGoogleSignInIsDoneWithoutTheVerificationStep() async {
        answer(.json(tokens))
        let vm = model()
        vm.google(idToken: "id-token")
        let state = await settled(vm)
        XCTAssertTrue(state.done)
        XCTAssertTrue(state.googleSignedIn)
        XCTAssertTrue(server.requests.contains { $0.path == "/api/v1/auth/google" })
    }

    func testRegisteringStillAsksToVerifyTheEmail() async {
        answer(.json(tokens))
        let vm = model()
        vm.register(name: "Amina", email: "student@example.test", password: "password123")
        let state = await settled(vm)
        XCTAssertTrue(state.done)
        XCTAssertFalse(state.googleSignedIn)
    }

    func testGoogleRegistrationWaitsForThePolicies() {
        let vm = model()
        vm.policiesNotAccepted()
        XCTAssertEqual(vm.state.error, "Please agree to the Terms & Conditions and Privacy Policy to continue.")
    }

    func testAGoogleStudentWithAnIncompleteProfileIsWelcomedOnce() async {
        answer(.json(tokens))
        let vm = model()
        vm.google(idToken: "id-token")
        _ = await settled(vm)
        let incomplete = ApiResult<Profile>.success(Profile(id: "u1", email: "student@example.test", role: "USER"))
        let first = await GoogleWelcome.consume { incomplete }
        let second = await GoogleWelcome.consume { incomplete }
        XCTAssertTrue(first)
        XCTAssertFalse(second) // once per sign-in
    }

    func testAFailedGoogleSignInWelcomesNoOne() async {
        answer(.json(#"{"success":false,"error":"Invalid Google ID token."}"#, status: 401))
        let vm = model()
        vm.google(idToken: "id-token")
        let state = await settled(vm)
        XCTAssertEqual(state.error, "Invalid Google ID token.")
        let welcomed = await GoogleWelcome.consume { .success(Profile(id: "u1", email: "s@example.test")) }
        XCTAssertFalse(welcomed)
    }

    func testOnlyStudentsWithAnIncompleteProfileAreSentToTheForm() {
        let profile = Profile(id: "u1", email: "s@example.test")
        XCTAssertTrue(needsProfileAfterGoogle(.success(profile)))
        var complete = profile
        complete.profileComplete = true
        XCTAssertFalse(needsProfileAfterGoogle(.success(complete)))
        var teacher = profile
        teacher.role = "TEACHER"
        XCTAssertFalse(needsProfileAfterGoogle(.success(teacher)))
        XCTAssertFalse(needsProfileAfterGoogle(.failure(ApiError(message: "offline"))))
    }

    /// Not in Android's test: an unverified account offers the verification e-mail again.
    func testAnUnverifiedAccountCanAskForTheEmailAgain() async {
        answer(.json(#"{"error":"Please verify your email.","code":"email_not_verified"}"#, status: 403))
        let vm = model()
        vm.login(email: " student@example.test ", password: "password123")
        let state = await settled(vm)
        XCTAssertEqual(state.unverifiedEmail, "student@example.test")
        XCTAssertFalse(state.busy)
    }
}
