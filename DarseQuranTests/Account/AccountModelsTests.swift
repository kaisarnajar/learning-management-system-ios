import XCTest
@testable import DarseQuran

/// Ported from Android's AccountViewModelsTest: the reviews and waiver models against a stub server.
@MainActor
final class AccountModelsTests: XCTestCase {
    private final class Posted: @unchecked Sendable {
        let lock = NSLock()
        var bodies: [Data] = []
    }

    private var server: StubServer!
    private var posted: Posted!
    private var repo: AcademyRepository!
    private var auth: AuthRepository!

    override func setUp() async throws {
        let server = StubServer()
        let posted = Posted()
        server.handler = { request in
            if request.method == "POST" { posted.lock.withLock { posted.bodies.append(request.body) } }
            switch request.path {
            case "/api/v1/auth/me": return .json(#"{"user":{"id":"u","email":"a@b.c","address":"Srinagar"}}"#)
            case "/api/v1/reviews", "/api/v1/waiver-requests": return .json(#"{"success":true,"data":[]}"#)
            case "/api/v1/courses":
                let page = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value
                return page == "1"
                    ? .json(#"{"data":[{"id":"1","title":"Tajweed","status":"ONGOING"},{"id":"2","title":"Fiqh","status":"COMPLETED"}],"totalCount":3,"page":1,"pageSize":50}"#)
                    : .json(#"{"data":[{"id":"3","title":"Arabic","status":"PUBLISHED"}],"totalCount":3,"page":2,"pageSize":50}"#)
            default: return .json(#"{"error":"Not found"}"#, status: 404)
            }
        }
        CurrentEnvironment.testBaseUrl = server.baseUrl
        let sessions = SessionStore(store: MemoryStore(), initialEnvironment: CurrentEnvironment.value)
        let api = AcademyAPI(client: APIClient(sessions: sessions, urlSession: server.session))
        self.server = server
        self.posted = posted
        repo = AcademyRepository(api: api)
        auth = AuthRepository(api: api, sessionStore: sessions)
    }

    override func tearDown() async throws {
        CurrentEnvironment.testBaseUrl = nil
        server = nil
    }

    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 5) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > end { XCTFail("timed out"); return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testAReviewStartsUnratedWithTheAddressAsItsLocationAndSendsTheWebsitesFields() async throws {
        let model = ReviewsModel(repo: repo, auth: auth)
        try await waitUntil { model.state.value != nil }
        XCTAssertEqual(ReviewDraft(rating: 0, location: "Srinagar"), model.draft)

        model.edit { $0.quote = "A wonderful course with patient teachers." }
        XCTAssertNil(model.send(), "nothing is sent without a rating")
        XCTAssertFalse(model.sending)
        XCTAssertTrue(posted.lock.withLock { posted.bodies.isEmpty }, "nothing is sent without a rating")

        model.edit { $0.rating = 4 }
        let first = model.send()
        XCTAssertNil(model.send(), "a double tap sends one review")
        await first?.value
        let bodies = posted.lock.withLock { posted.bodies }
        XCTAssertEqual(1, bodies.count)
        let sent = try JSONSerialization.jsonObject(with: bodies[0]) as? NSDictionary
        XCTAssertEqual(["quote": "A wonderful course with patient teachers.", "rating": 4, "location": "Srinagar"] as NSDictionary, sent)
        XCTAssertEqual(reviewSent, model.message?.text)
        XCTAssertEqual(ReviewDraft(location: "Srinagar"), model.draft)
    }

    func testTheWaiverFormOffersEveryOpenCourseFromAllPages() async throws {
        let model = WaiversModel(repo: repo)
        try await waitUntil { model.state.value != nil }
        XCTAssertEqual(["Arabic", "Tajweed"], model.state.value?.courses.map(\.title))
    }
}
