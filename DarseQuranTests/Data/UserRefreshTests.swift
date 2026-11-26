import XCTest
@testable import DarseQuran

/// Ported from Android's UserRefreshTest.
final class UserRefreshTests: XCTestCase {
    private let here = CurrentEnvironment.value
    private var server: StubServer!

    override func setUp() {
        server = StubServer()
        server.handler = { request in
            request.path == "/api/v1/auth/me"
                ? .json(#"{"user":{"id":"u1","email":"staff@example.test","role":"USER"}}"#)
                : .json("{}", status: 404) // e.g. the cart, fetched on sign-in
        }
        CurrentEnvironment.testBaseUrl = server.baseUrl
    }

    override func tearDown() {
        CurrentEnvironment.testBaseUrl = nil
        CurrentEnvironment.value = here
        server = nil
    }

    private var profileCalls: Int { server.requests.filter { $0.path == "/api/v1/auth/me" }.count }

    @MainActor
    func testARoleChangedOnTheWebsiteReachesTheApp() async {
        let app = makeTestContainer(server: server)
        app.sessionStore.save(TokenResponse(
            accessToken: "a", refreshToken: "r", user: SessionUser(id: "u1", email: "staff@example.test", role: "ADMIN")
        ))
        let start = Date(timeIntervalSince1970: 1_000_000)
        app.refreshUserIfStale(now: start)
        await waitFor("the new role") { app.sessionStore.current?.user.role == "USER" }
        await waitFor("the app's copy of the session") { app.session?.user.role == "USER" }
        app.refreshUserIfStale(now: start.addingTimeInterval(60)) // a minute later: not again
        app.refreshUserIfStale(now: start.addingTimeInterval(9 * 60))
        await settle(for: .milliseconds(200))
        XCTAssertEqual(1, profileCalls)
        app.refreshUserIfStale(now: start.addingTimeInterval(10 * 60)) // ten minutes on: again
        await waitFor("a second check") { self.profileCalls == 2 }
    }
}
