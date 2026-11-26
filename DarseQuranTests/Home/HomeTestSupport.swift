import Foundation
import XCTest
@testable import DarseQuran

/// A Keychain stand-in that keeps the session in memory.
final class MemorySecureStore: SecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    func read(_ account: String) -> Data? { lock.withLock { items[account] } }
    func write(_ data: Data, account: String) { lock.withLock { items[account] = data } }
    func delete(_ account: String) { _ = lock.withLock { items.removeValue(forKey: account) } }
}

/// The repositories the screens' models use, talking to a [StubServer] (Android's app.container under MockWebServer).
struct TestApp {
    let sessionStore: SessionStore
    let repo: AcademyRepository
    let auth: AuthRepository

    init(_ server: StubServer, savedHome: SavedHome? = nil) { self.init(session: server.session, savedHome: savedHome) }
    init(_ server: SlowStubServer, savedHome: SavedHome? = nil) { self.init(session: server.session, savedHome: savedHome) }

    init(session: URLSession, savedHome: SavedHome?) {
        sessionStore = SessionStore(store: MemorySecureStore(), initialEnvironment: CurrentEnvironment.value)
        let api = AcademyAPI(client: APIClient(sessions: sessionStore, urlSession: session))
        let fileFor: (@Sendable (AppEnvironment) -> SavedHome)? = savedHome.map { saved in { @Sendable _ in saved } }
        repo = AcademyRepository(api: api, savedHome: fileFor)
        auth = AuthRepository(api: api, sessionStore: sessionStore)
    }

    func signIn(access: String = "a", refresh: String = "r", user: String = "u1") {
        sessionStore.save(TokenResponse(accessToken: access, refreshToken: refresh, user: SessionUser(id: user, email: "student@example.test")))
    }
}

