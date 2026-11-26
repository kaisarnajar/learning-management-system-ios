import XCTest
@testable import DarseQuran

/// Ported from Android's CourseDetailViewModelTest and CourseCatalogueTest (the catalogue at model level: the shared
/// pager it renders from loads page 1, then page 2).
@MainActor
final class CourseModelsTests: XCTestCase {
    private var server: StubServer!
    private var backend: StubBackend!
    private let enrolls = Box(0)

    override func setUp() async throws {
        server = StubServer()
        let enrolls = enrolls
        server.handler = { request in
            let signedIn = request.authorization != nil
            switch request.path {
            case "/api/v1/courses/c1":
                return .json(#"{"course":{"id":"c1","title":"Tajweed"},"enrollmentOpen":true"#
                    + (signedIn ? #","enrollment":{"id":"e1","courseId":"c1","status":"awaiting_enrollment_fee"}}"# : "}"))
            case "/api/v1/enrollments" where request.method == "POST":
                enrolls.update { $0 += 1 }
                Thread.sleep(forTimeInterval: 0.2)
                return .json(#"{"success":true,"requiresEnrollmentFee":true}"#)
            case "/api/v1/courses":
                let page = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value ?? "1"
                return .json(#"{"data":[{"id":"c\#(page)","title":"Course page \#(page)"}],"totalCount":2,"page":\#(page),"pageSize":1}"#)
            default:
                return .json("{}", status: 404)
            }
        }
        CurrentEnvironment.testBaseUrl = server.baseUrl
        backend = StubBackend(server)
    }

    override func tearDown() async throws {
        CurrentEnvironment.testBaseUrl = nil
        server = nil
        backend = nil
    }

    private func detailModel() async -> CourseDetailModel {
        let vm = CourseDetailModel(repo: backend.repo, auth: backend.auth, courseId: "c1")
        await waitUntil { vm.state.value != nil }
        return vm
    }

    func testSigningInShowsTheEnrollment() async {
        let vm = await detailModel()
        XCTAssertNil(vm.state.value?.enrollment)
        backend.signIn()
        await waitUntil { vm.state.value?.enrollment != nil }
        XCTAssertEqual("awaiting_enrollment_fee", vm.state.value?.enrollment?.status)
        XCTAssertTrue(vm.signedIn)
    }

    func testADoubleTapAppliesOnce() async {
        let vm = await detailModel()
        vm.apply(); vm.apply()
        await waitUntil { !vm.busy }
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(1, enrolls.value)
    }

    func testAPaidCourseSendsTheStudentOnToPayThroughState() async {
        let vm = await detailModel()
        vm.apply()
        await waitUntil { vm.next != nil }
        XCTAssertEqual(.pay, vm.next)
        vm.consumeNext()
        XCTAssertNil(vm.next)
    }

    func testCataloguePagesThroughTheSharedPager() async {
        let model = CoursesModel(repo: backend.repo, auth: backend.auth)
        await waitUntil { model.catalogue.state.items.map(\.title) == ["Course page 1"] }
        model.catalogue.loadMore()
        await waitUntil { model.catalogue.state.items.map(\.title) == ["Course page 1", "Course page 2"] }
        XCTAssertFalse(model.catalogue.state.canLoadMore)
        // Signed out: no courses of one's own, and no request for them.
        await waitUntil { model.mine == .ready([]) }
        XCTAssertFalse(server.requests.contains { $0.path == "/api/v1/enrollments" })
    }
}
