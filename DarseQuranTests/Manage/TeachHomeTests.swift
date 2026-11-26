import XCTest
@testable import DarseQuran

/// Ported from Android's ui/teach/TeachHomeTest.kt.
@MainActor
final class TeachHomeTests: XCTestCase {
    private var server: StubServer!

    override func setUp() async throws {
        server = StubServer()
        server.handler = { request in
            request.path == "/api/v1/teacher/courses"
                ? .json(#"""
                  {"data":[{"id":"c1","title":"Tajweed basics"}],"totalCount":1,
                   "teacher":{"name":"Ustadh Bilal","email":"bilal@example.test"},"stats":{"totalCourses":1,"totalStudents":12}}
                  """#)
                : .json("{}", status: 404)
        }
    }

    override func tearDown() async throws { CurrentEnvironment.testBaseUrl = nil; server = nil }

    func testOneRequestFillsTheHeaderAndTheFirstPage() async {
        let model = TeachHomeModel(app: testContainer(server))
        await waitUntil { model.header.home != nil && !model.courses.state.loading }
        XCTAssertEqual("Ustadh Bilal", model.header.home?.teacher.name)
        XCTAssertEqual(12, model.header.home?.stats.totalStudents)
        XCTAssertEqual(["Tajweed basics"], model.courses.state.items.map(\.title))
        XCTAssertEqual(1, server.requests.filter { $0.path == "/api/v1/teacher/courses" }.count)
    }
}
