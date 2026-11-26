import XCTest
@testable import DarseQuran

/// The marks belong to the screen's model, so the view being rebuilt keeps them and saving can't overwrite stored
/// absences. Ported from Android's ui/manage/courses/AttendanceRestoreTest.kt (a rotation there).
@MainActor
final class AttendanceRestoreTests: XCTestCase {
    private var server: StubServer!

    override func setUp() async throws {
        server = StubServer()
        server.handler = { request in
            if request.method == "GET", request.path.hasSuffix("/attendance/students") {
                return .json(#"""
                {"data":[
                  {"enrollmentId":"e1","rollNumberLabel":"1","name":"Amina","email":"amina@example.test"},
                  {"enrollmentId":"e2","rollNumberLabel":"2","name":"Bilal","email":"bilal@example.test"}]}
                """#)
            }
            if request.method == "PUT" { return .json(#"{"success":true}"#) }
            return .json("{}", status: 404)
        }
    }

    override func tearDown() async throws { CurrentEnvironment.testBaseUrl = nil; server = nil }

    func testMarksSurviveRecreationAndAreSaved() async throws {
        let model = AttendanceTakeModel(app: testContainer(server), portal: .teacher, courseId: "c1", date: nil)
        await waitUntil { model.ready }
        model.initialise()

        model.toggle("e1") // present → absent
        XCTAssertEqual(1, model.presentCount)

        // The view is rebuilt (it asks to fill the form again): the marks stay.
        model.initialise()
        XCTAssertEqual(1, model.presentCount)
        XCTAssertFalse(model.isPresent("e1"))

        var done = false
        model.save { done = true }
        await waitUntil { done }
        XCTAssertEqual(3, server.requests.count, "students, the day check, then the save")
        let put = try XCTUnwrap(server.requests.first { $0.method == "PUT" })
        let body = try XCTUnwrap(put.json(AttendanceSave.self))
        XCTAssertEqual(["e1": false, "e2": true], Dictionary(uniqueKeysWithValues: body.records.map { ($0.enrollmentId, $0.isPresent) }))
    }
}
