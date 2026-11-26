import XCTest
@testable import DarseQuran

/// Ported from Android's DocumentCacheTest.
final class DocumentCacheTests: XCTestCase {
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

    private func receipt() throws -> URL {
        let file = DocumentCache.file(named: "receipt.pdf")
        try Data("%PDF".utf8).write(to: file)
        return file
    }

    @MainActor
    private func signIn(_ app: AppContainer, _ id: String) async {
        app.sessionStore.save(TokenResponse(accessToken: "a-\(id)", refreshToken: "r-\(id)", user: SessionUser(id: id, email: "\(id)@example.test")))
        await waitFor("\(id) signed in") { app.session?.user.id == id }
    }

    @MainActor
    func testSigningOutClearsOpenedDocuments() async throws {
        let app = makeTestContainer(server: server)
        await signIn(app, "u1")
        let file = try receipt()
        app.sessionStore.clear()
        await waitFor("the document to go") { !FileManager.default.fileExists(atPath: file.path) }
    }

    @MainActor
    func testATokenRefreshForTheSameUserKeepsThem() async throws {
        let app = makeTestContainer(server: server)
        await signIn(app, "u1")
        let file = try receipt()
        await signIn(app, "u1") // a new token pair, same user
        await settle(for: .milliseconds(300))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        app.sessionStore.clear()
    }

    /// Not in Android's test, but Android's rule: its container clears the documents whenever the session's user id
    /// changes, and switching servers (debug build) swaps in the other server's session.
    @MainActor
    func testSwitchingToAServerWithoutThatUserClearsThem() async throws {
        let app = makeTestContainer(server: server)
        app.switchEnvironment(.staging)
        await signIn(app, "u1")
        let file = try receipt()
        app.switchEnvironment(.production) // nobody signed in there
        await waitFor("the document to go") { !FileManager.default.fileExists(atPath: file.path) }
        app.switchEnvironment(.staging)
        app.sessionStore.clear()
    }
}
