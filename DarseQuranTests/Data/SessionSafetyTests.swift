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

/// Observers that belong to a screen's model end with it (Android: the collector ends with viewModelScope).
final class SessionObserverTests: XCTestCase {
    func testAnObserverIsDroppedOnceItsOwnerIsGone() {
        let store = SessionStore(store: MemoryStore(), initialEnvironment: .staging)
        store.observe { _ in } // the app's own, for its whole life
        var owner: NSObject? = NSObject()
        store.observe(owner: owner) { _ in }
        XCTAssertEqual(2, store.observerCount)
        owner = nil
        store.save(TokenResponse(accessToken: "a", refreshToken: "r", user: SessionUser(id: "u1", email: "one@example.test")))
        XCTAssertEqual(1, store.observerCount)
    }
}

/// A fresh install starts signed out (Keychain items outlive an uninstall; Android's data doesn't).
final class FreshInstallTests: XCTestCase {
    func testAFreshInstallForgetsSessionsLeftInTheKeychainButOnlyOnce() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "fresh-install-test"))
        defaults.removePersistentDomain(forName: "fresh-install-test")
        let keychain = MemoryStore()
        keychain.write(Data("old".utf8), account: AppEnvironment.staging.key)
        keychain.write(Data("old".utf8), account: AppEnvironment.production.key)
        forgetSessionsFromAnEarlierInstall(keychain, defaults: defaults)
        XCTAssertNil(keychain.read(AppEnvironment.staging.key))
        XCTAssertNil(keychain.read(AppEnvironment.production.key))
        // Later launches keep the sign-in.
        keychain.write(Data("new".utf8), account: AppEnvironment.staging.key)
        forgetSessionsFromAnEarlierInstall(keychain, defaults: defaults)
        XCTAssertNotNil(keychain.read(AppEnvironment.staging.key))
    }
}
