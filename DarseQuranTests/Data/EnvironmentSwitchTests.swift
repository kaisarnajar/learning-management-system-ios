import XCTest
@testable import DarseQuran

/// Switching servers in the debug build keeps a separate sign-in on each. Ported from Android's EnvironmentSwitchTest.
final class EnvironmentSwitchTests: XCTestCase {
    private let here = CurrentEnvironment.value
    private var server: StubServer!

    override func setUp() {
        server = StubServer()
        server.handler = { _ in .json("{}", status: 404) }
        CurrentEnvironment.testBaseUrl = server.baseUrl
    }

    override func tearDown() {
        CurrentEnvironment.testBaseUrl = nil
        CurrentEnvironment.value = here
        server = nil
    }

    @MainActor
    func testEachServerKeepsItsOwnSignIn() {
        let container = makeTestContainer(server: server)
        let staging = AppEnvironment.staging
        let production = AppEnvironment.production
        container.switchEnvironment(staging)
        let user = SessionUser(id: "u-staging", email: "s@example.test", role: "USER")
        container.sessionStore.save(TokenResponse(accessToken: "a", refreshToken: "r", user: user))

        container.switchEnvironment(production)
        XCTAssertEqual(production, CurrentEnvironment.value)
        XCTAssertEqual(production, container.environment)
        XCTAssertNil(container.sessionStore.current, "production has no sign-in yet")
        XCTAssertNil(container.session)

        container.switchEnvironment(staging)
        XCTAssertEqual("u-staging", container.sessionStore.current?.user.id)
        XCTAssertEqual(staging, container.sessionStore.current?.env)
        XCTAssertEqual("u-staging", container.session?.user.id)
    }

    @MainActor
    func testTheChosenServerIsRememberedForTheNextRun() {
        let defaults = UserDefaults(suiteName: "tests-\(UUID().uuidString)")!
        EnvironmentStore(defaults: defaults).select(.production)
        XCTAssertEqual(.production, EnvironmentStore(defaults: defaults).initial)
        XCTAssertEqual(.production, CurrentEnvironment.value)
        defaults.set("local", forKey: "environment") // a server this build no longer has
        XCTAssertEqual(AppEnvironment.defaultEnvironment, EnvironmentStore(defaults: defaults).initial)
    }
}
