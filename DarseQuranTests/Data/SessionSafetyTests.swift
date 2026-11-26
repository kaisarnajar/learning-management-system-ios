import XCTest
@testable import DarseQuran

/// Signing out and profile refreshes can't leave the wrong person signed in. Ported from Android's SessionSafetyTest.
final class SessionSafetyTests: XCTestCase {
    private let here = CurrentEnvironment.value
    private var server: StubServer!
    private let releaseLogout = DispatchSemaphore(value: 0)

    override func setUp() {
        server = StubServer()
        let release = releaseLogout
        server.handler = { request in
            if request.path == "/api/v1/auth/logout" {
                _ = release.wait(timeout: .now() + 10) // a server that is slow to answer
                return .json(#"{"ok":true}"#)
            }
            return .json("{}", status: 404)
        }
        CurrentEnvironment.testBaseUrl = server.baseUrl
    }

    override func tearDown() {
        releaseLogout.signal()
        CurrentEnvironment.testBaseUrl = nil
        CurrentEnvironment.value = here
        server = nil
    }

    private func signedIn(_ store: SessionStore) -> SessionStore {
        store.save(TokenResponse(accessToken: "a", refreshToken: "r", user: SessionUser(id: "u1", email: "one@example.test")))
        return store
    }

    func testAProfileForSomeoneElseDoesNotOverwriteTheSession() {
        let store = signedIn(SessionStore(store: MemoryStore(), initialEnvironment: .staging))
        store.save(TokenResponse(accessToken: "b", refreshToken: "r2", user: SessionUser(id: "u2", email: "two@example.test")))
        store.updateUser(SessionUser(id: "u1", email: "one@example.test", role: "ADMIN"))
        let user = store.current?.user
        XCTAssertEqual("u2", user?.id)
        XCTAssertEqual("USER", user?.role)
    }

    @MainActor
    func testLeavingTheScreenWhileSigningOutStillSignsOut() async {
        let container = makeTestContainer(server: server)
        let store = signedIn(container.sessionStore)
        let auth = container.auth
        let screen = Task { await auth.logout() }
        let server = server!
        await waitFor("the logout request to reach the server") { server.requests.contains { $0.path == "/api/v1/auth/logout" } }
        screen.cancel() // the Account screen goes away
        releaseLogout.signal()
        await waitFor("signed out") { store.current == nil }
    }
}
