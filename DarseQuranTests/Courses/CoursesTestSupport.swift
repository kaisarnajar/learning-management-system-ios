import Foundation
import XCTest
@testable import DarseQuran

/// The repositories the screens' models use, talking to a [StubServer] (Android's app.container against MockWebServer).
struct StubBackend {
    let sessions: SessionStore
    let repo: AcademyRepository
    let auth: AuthRepository

    init(_ server: StubServer) {
        sessions = SessionStore(store: MemoryStore(), initialEnvironment: CurrentEnvironment.value)
        let api = AcademyAPI(client: APIClient(sessions: sessions, urlSession: server.session))
        repo = AcademyRepository(api: api)
        auth = AuthRepository(api: api, sessionStore: sessions)
    }

    func signIn() {
        sessions.save(TokenResponse(accessToken: "a", refreshToken: "r", user: SessionUser(id: "u1", email: "student@example.test")))
    }
}


/// A thread-safe counter / box for values seen by a stub server's handler.
final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { _value = value }
    var value: T {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
    func update(_ f: (inout T) -> Void) { lock.withLock { f(&_value) } }
}
