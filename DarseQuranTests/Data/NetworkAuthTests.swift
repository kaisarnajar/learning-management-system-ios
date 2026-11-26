import XCTest
@testable import DarseQuran

/// The token handling of [APIClient]: the Bearer header, refresh on 401, and when it must not refresh.
/// Ported from Android's NetworkAuthTest (URLProtocol stubs instead of MockWebServer).
final class NetworkAuthTests: XCTestCase {

    private final class FakeSession: SessionSource, @unchecked Sendable {
        private let lock = NSLock()
        private var state: Session?
        private var _savedFor: [AppEnvironment] = []
        init(_ initial: Session?) { state = initial }

        var current: Session? { lock.withLock { state } }
        var savedFor: [AppEnvironment] { lock.withLock { _savedFor } }

        func saveRefreshed(_ old: Session, _ tokens: TokenResponse) {
            lock.withLock {
                _savedFor.append(old.env)
                if state?.env == old.env { state = Session(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken, user: old.user, env: old.env) }
            }
        }

        func expire(_ old: Session) {
            lock.withLock { if state?.refreshToken == old.refreshToken { state = nil } }
        }
    }

    /// Tokens the fake server accepts; "refresh-1" is exchanged once for "access-2".
    private final class Backend: @unchecked Sendable {
        let lock = NSLock()
        var validAccess = "access-1"
        var refreshStatus = 200
        var refreshCalls = 0
        var seenAuth: [String?] = []
        var switchDuringRefresh = false
    }

    private let user = SessionUser(id: "u1", email: "student@example.test")
    private let here = CurrentEnvironment.value
    private var elsewhere: AppEnvironment { AppEnvironment.allCases.first { $0 != here }! }
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private var server: StubServer!
    private var backend: Backend!

    override func setUp() {
        server = StubServer()
        backend = Backend()
        let backend = backend!
        let elsewhere = self.elsewhere
        server.handler = { request in
            if request.path == "/api/v1/auth/refresh" {
                backend.lock.lock()
                backend.refreshCalls += 1
                let switching = backend.switchDuringRefresh
                let status = backend.refreshStatus
                backend.lock.unlock()
                if switching { CurrentEnvironment.value = elsewhere }
                Thread.sleep(forTimeInterval: 0.05) // long enough for concurrent 401s to queue behind the refresher
                if status != 200 { return .json(#"{"error":"Session expired."}"#, status: status) }
                backend.lock.withLock { backend.validAccess = "access-2" }
                return .json(#"{"accessToken":"access-2","refreshToken":"refresh-2"}"#)
            }
            return backend.lock.withLock {
                backend.seenAuth.append(request.authorization)
                return request.authorization == "Bearer \(backend.validAccess)"
                    ? .json(#"{"success":true}"#) : .json(#"{"error":"Unauthorized"}"#, status: 401)
            }
        }
        CurrentEnvironment.testBaseUrl = server.baseUrl
    }

    override func tearDown() {
        CurrentEnvironment.testBaseUrl = nil
        CurrentEnvironment.value = here
        server = nil
    }

    private func session(env: AppEnvironment? = nil, expiresAt: Date? = nil) -> Session {
        Session(accessToken: "access-1", refreshToken: "refresh-1", user: user, env: env ?? here, expiresAt: expiresAt)
    }

    private func client(_ session: Session?) -> (FakeSession, APIClient) {
        let fake = FakeSession(session)
        let now = self.now
        return (fake, APIClient(sessions: fake, urlSession: server.session, clock: { now }))
    }

    private static func ping(_ client: APIClient) async throws { let _: OkResponse = try await client.get("ping") }
    private var seenAuth: [String?] { backend.lock.withLock { backend.seenAuth } }
    private var refreshCalls: Int { backend.lock.withLock { backend.refreshCalls } }

    func testSignedInRequestsCarryTheBearerToken() async throws {
        let (_, api) = client(session())
        try await Self.ping(api)
        XCTAssertEqual(seenAuth, ["Bearer access-1"])
    }

    func testAnotherEnvironmentsSessionIsNotSent() async {
        let (_, api) = client(session(env: elsewhere))
        try? await Self.ping(api)
        XCTAssertEqual(seenAuth, [nil])
        XCTAssertEqual(refreshCalls, 0)
    }

    func testARefreshThatFinishesAfterASwitchIsStoredForTheOldEnvironmentAndNotRetried() async {
        backend.validAccess = "expired"
        backend.switchDuringRefresh = true
        let (fake, api) = client(session())
        do { try await Self.ping(api); XCTFail("expected 401") } catch { XCTAssertEqual((error as? HTTPError)?.status, 401) }
        XCTAssertEqual(fake.savedFor, [here])
        XCTAssertEqual(seenAuth, ["Bearer access-1"]) // the new token never went anywhere
    }

    func testAnotherHostNeverSeesTheToken() async {
        let (_, api) = client(session())
        let _: OkResponse? = try? await api.get("https://elsewhere.test/file")
        XCTAssertEqual(seenAuth, [nil])
    }

    func testTheSameHostOnAnotherPortNeverSeesTheToken() async {
        let (_, api) = client(session())
        let host = URL(string: server.baseUrl)!.host!
        let _: OkResponse? = try? await api.get("https://\(host):8443/file")
        XCTAssertEqual(seenAuth, [nil])
    }

    func testSignedOutRequestsHaveNoAuthorizationAndAreNotRefreshed() async {
        let (_, api) = client(nil)
        do { try await Self.ping(api); XCTFail("expected 401") } catch { XCTAssertEqual((error as? HTTPError)?.status, 401) }
        XCTAssertEqual(seenAuth, [nil])
        XCTAssertEqual(refreshCalls, 0)
    }

    func testA401RefreshesOnceAndRetriesWithTheNewToken() async throws {
        backend.validAccess = "expired" // the stored access-1 is no longer accepted
        let (fake, api) = client(session())
        try await Self.ping(api)
        XCTAssertEqual(refreshCalls, 1)
        XCTAssertEqual(seenAuth, ["Bearer access-1", "Bearer access-2"])
        XCTAssertEqual(fake.current?.accessToken, "access-2")
        XCTAssertEqual(fake.current?.refreshToken, "refresh-2")
    }

    func testConcurrent401sShareOneRefresh() async throws {
        backend.validAccess = "expired"
        let (fake, api) = client(session())
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 1...3 { group.addTask { try await Self.ping(api) } }
            try await group.waitForAll()
        }
        XCTAssertEqual(refreshCalls, 1)
        XCTAssertEqual(fake.current?.accessToken, "access-2")
    }

    /// More 401s than a connection pool's per-host limit once deadlocked Android's refresh.
    func testManyConcurrent401sDoNotDeadlockTheRefresh() async throws {
        backend.validAccess = "expired"
        let (fake, api) = client(session())
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 1...10 { group.addTask { try await Self.ping(api) } }
            try await group.waitForAll()
        }
        XCTAssertEqual(refreshCalls, 1)
        XCTAssertEqual(fake.current?.accessToken, "access-2")
    }

    func testARejectedRefreshTokenSignsOut() async {
        backend.validAccess = "expired"
        backend.refreshStatus = 401
        let (fake, api) = client(session())
        do { try await Self.ping(api); XCTFail("expected 401") } catch { XCTAssertEqual((error as? HTTPError)?.status, 401) }
        XCTAssertNil(fake.current)
    }

    func testAServerErrorDuringRefreshKeepsTheSession() async {
        backend.validAccess = "expired"
        backend.refreshStatus = 500
        let (fake, api) = client(session())
        try? await Self.ping(api)
        XCTAssertEqual(fake.current?.accessToken, "access-1")
    }

    func testA401FromAnotherHostIsNotRefreshed() async {
        let (_, api) = client(session())
        do { let _: OkResponse = try await api.get("https://elsewhere.test/file"); XCTFail("expected an error") } catch {}
        XCTAssertEqual(refreshCalls, 0)
    }

    func testATokenAboutToRunOutIsRefreshedBeforeTheRequestInsteadOfAfterA401() async throws {
        backend.validAccess = "expired"
        let (fake, api) = client(session(expiresAt: now.addingTimeInterval(30)))
        try await Self.ping(api)
        XCTAssertEqual(refreshCalls, 1)
        XCTAssertEqual(seenAuth, ["Bearer access-2"]) // the stale token was never sent
        XCTAssertEqual(fake.current?.accessToken, "access-2")
    }

    func testConcurrentRequestsWithAnExpiringTokenShareOneRefresh() async throws {
        backend.validAccess = "expired"
        let (_, api) = client(session(expiresAt: now.addingTimeInterval(-0.001)))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 1...10 { group.addTask { try await Self.ping(api) } }
            try await group.waitForAll()
        }
        XCTAssertEqual(refreshCalls, 1)
        XCTAssertEqual(seenAuth, Array(repeating: "Bearer access-2", count: 10))
    }

    func testATokenWithTimeLeftIsNotRefreshed() async throws {
        let (_, api) = client(session(expiresAt: now.addingTimeInterval(600)))
        try await Self.ping(api)
        XCTAssertEqual(refreshCalls, 0)
        XCTAssertEqual(seenAuth, ["Bearer access-1"])
    }

    func testAFailedEarlyRefreshStillSendsTheCurrentToken() async throws {
        backend.refreshStatus = 500
        let (fake, api) = client(session(expiresAt: now))
        try await Self.ping(api) // access-1 is still accepted by the server
        XCTAssertEqual(seenAuth, ["Bearer access-1"])
        XCTAssertEqual(fake.current?.accessToken, "access-1")
    }

    func testARejectedEarlyRefreshSignsOutAndSendsNoToken() async {
        backend.refreshStatus = 401
        let (fake, api) = client(session(expiresAt: now))
        try? await Self.ping(api)
        XCTAssertNil(fake.current)
        XCTAssertEqual(seenAuth, [nil])
    }

    func testAnotherHostIsNotAReasonToRefresh() async {
        let (_, api) = client(session(expiresAt: now))
        let _: OkResponse? = try? await api.get("https://elsewhere.test/file")
        XCTAssertEqual(refreshCalls, 0)
    }
}
