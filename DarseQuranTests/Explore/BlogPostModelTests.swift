import XCTest
@testable import DarseQuran

/// Ported from Android's BlogPostViewModelTest.
@MainActor
final class BlogPostModelTests: XCTestCase {
    private var server: SlowStubServer!
    private var app: TestApp!

    override func setUp() async throws {
        server = SlowStubServer()
        server.handler = { request in
            let signedIn = request.authorization != nil
            switch request.path {
            case "/api/v1/blog/p1":
                return (.json(#"{"post":{"id":"p1","title":"Patience","likedByMe":\#(signedIn)}}"#), 0)
            case "/api/v1/blog/p1/comments":
                if request.method == "POST" { return (.json(#"{"comment":{"id":"c1","content":"JazakAllah"}}"#), 0.3) }
                return (.json(#"{"data":[]}"#), 0)
            case "/api/v1/blog/p1/like":
                return (.json(#"{"liked":true,"likeCount":1}"#), 0.3)
            default:
                return (.json("{}", status: 404), 0)
            }
        }
        CurrentEnvironment.testBaseUrl = server.baseUrl
        app = TestApp(server)
    }

    override func tearDown() async throws {
        app.sessionStore.clear()
        CurrentEnvironment.testBaseUrl = nil
        server = nil
    }

    private func model() -> BlogPostModel { BlogPostModel(repo: app.repo, auth: app.auth, id: "p1") }
    private func count(_ method: String, _ path: String) -> Int { server.requests.filter { $0.method == method && $0.path == path }.count }

    func testASecondTapWhileLikingIsIgnored() async throws {
        app.signIn()
        let vm = model()
        await waitUntil { vm.post.value != nil }
        vm.like(); vm.like(); vm.like()
        await waitUntil { vm.post.value?.likeCount == 1 }
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(count("POST", "/api/v1/blog/p1/like"), 1)
    }

    func testASecondTapWhilePostingACommentIsIgnored() async throws {
        let vm = model()
        await waitUntil { vm.post.value != nil }
        var done = 0
        vm.comment("JazakAllah") { done += 1 }
        vm.comment("JazakAllah") { done += 1 }
        await waitUntil { done > 0 }
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(count("POST", "/api/v1/blog/p1/comments"), 1)
        XCTAssertEqual(done, 1)
        XCTAssertEqual(vm.comments.map(\.id), ["c1"])
    }

    func testSigningInReloadsThePost() async {
        let vm = model()
        await waitUntil { vm.post.value != nil }
        XCTAssertEqual(vm.post.value?.likedByMe, false)
        app.signIn()
        await waitUntil { vm.post.value?.likedByMe == true }
        XCTAssertGreaterThanOrEqual(count("GET", "/api/v1/blog/p1"), 2)
    }
}

/// Ported from Android's LibraryTopicsTest.
final class LibraryTopicsTests: XCTestCase {
    func testTheWebsitesTopicsInItsOrder() {
        XCTAssertEqual(libraryTopics.first, "Islam")
        XCTAssertEqual(Array(libraryTopics.suffix(3)), ["Fatwa", "Qiraat", "Other"])
    }

    func testTheEmptyLineNamesThePickedTopic() {
        XCTAssertEqual(libraryEmptyText(nil), "No library items available yet.")
        XCTAssertEqual(libraryEmptyText("Tajweed"), "No materials in “Tajweed” yet.")
    }
}
