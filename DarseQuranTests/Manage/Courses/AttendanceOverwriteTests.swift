import XCTest
@testable import DarseQuran

/// "Mark attendance" on a day that is already marked must not silently replace it. Ported from Android's
/// ui/manage/courses/AttendanceOverwriteTest.kt (the screen's rules live in AttendanceTakeModel).
@MainActor
final class AttendanceOverwriteTests: XCTestCase {
    private var server: StubServer!

    override func setUp() async throws { server = StubServer() }
    override func tearDown() async throws { CurrentEnvironment.testBaseUrl = nil; server = nil }

    private func answer(todayMarked: Bool) {
        let today = academyTodayIso()
        server.handler = { request in
            if request.path.hasSuffix("/attendance/students") {
                return .json(#"{"data":[{"enrollmentId":"e1","name":"Amina","email":"a@example.test"}]}"#)
            }
            if request.path.hasSuffix("/attendance/\(today)"), request.method == "GET" {
                return todayMarked
                    ? .json(#"{"date":"\#(today)","records":[{"enrollmentId":"e1","email":"a@example.test","isPresent":false}]}"#)
                    : .json(#"{"error":"Not found"}"#, status: 404)
            }
            if request.method == "PUT" { return .json(#"{"success":true}"#) }
            return .json("{}", status: 404)
        }
    }

    /// Opens the form for a new day and presses Save once the class has loaded.
    private func saveNewDay(onDone: @escaping () -> Void = {}) async -> AttendanceTakeModel {
        let model = AttendanceTakeModel(app: testContainer(server), portal: .teacher, courseId: "c1", date: nil)
        await waitUntil { model.ready }
        model.initialise()
        XCTAssertEqual(1, model.presentCount)
        model.save(onDone: onDone)
        return model
    }

    private var methods: [String] { server.requests.map(\.method) }

    func testAnAlreadyMarkedDayAsksInsteadOfReplacingIt() async {
        answer(todayMarked: true)
        let model = await saveNewDay()
        await waitUntil { model.alreadyMarked != nil }
        XCTAssertFalse(methods.contains("PUT"), "nothing was saved")

        XCTAssertEqual(academyTodayIso(), model.openMarkedDay())
        XCTAssertNil(model.alreadyMarked)
        XCTAssertFalse(methods.contains("PUT"))
    }

    func testANewDayIsSavedStraightAway() async {
        answer(todayMarked: false)
        var done = false
        let model = await saveNewDay { done = true }
        await waitUntil { done }
        XCTAssertTrue(methods.contains("PUT"))
        XCTAssertNil(model.alreadyMarked)
    }
}
