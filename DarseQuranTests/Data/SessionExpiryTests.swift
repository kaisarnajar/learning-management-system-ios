import XCTest
@testable import DarseQuran

/// The session remembers when its access token runs out, so the network layer can refresh it in time.
/// Ported from Android's SessionExpiryTest; "a restart" is a new SessionStore over the same secure store.
final class SessionExpiryTests: XCTestCase {
    private final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Date(timeIntervalSince1970: 5_000)
        var now: Date {
            get { lock.withLock { value } }
            set { lock.withLock { value = newValue } }
        }
    }

    private let user = SessionUser(id: "u1", email: "one@example.test")
    private let keychain = MemoryStore()
    private let clock = TestClock()

    private func store() -> SessionStore {
        let clock = clock
        return SessionStore(store: keychain, initialEnvironment: AppEnvironment.defaultEnvironment) { clock.now }
    }

    func testSigningInRecordsTheExpiryAndItSurvivesARestart() {
        store().save(TokenResponse(accessToken: "a", refreshToken: "r", expiresIn: 3600, user: user))
        XCTAssertEqual(clock.now.addingTimeInterval(3600), store().current?.expiresAt)
    }

    func testARefreshMovesTheExpiry() throws {
        let store = store()
        store.save(TokenResponse(accessToken: "a", refreshToken: "r", expiresIn: 3600, user: user))
        clock.now += 50 * 60
        store.saveRefreshed(try XCTUnwrap(store.current), TokenResponse(accessToken: "a2", refreshToken: "r2", expiresIn: 3600))
        XCTAssertEqual(clock.now.addingTimeInterval(3600), store.current?.expiresAt)
        XCTAssertEqual(clock.now.addingTimeInterval(3600), self.store().current?.expiresAt)
    }

    func testAProfileUpdateKeepsTheExpiry() {
        let store = store()
        store.save(TokenResponse(accessToken: "a", refreshToken: "r", expiresIn: 3600, user: user))
        var renamed = user
        renamed.name = "One"
        store.updateUser(renamed)
        XCTAssertEqual(clock.now.addingTimeInterval(3600), self.store().current?.expiresAt)
        XCTAssertEqual("One", self.store().current?.user.name)
    }
}
