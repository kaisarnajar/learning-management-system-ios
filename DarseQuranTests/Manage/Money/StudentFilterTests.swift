import XCTest
@testable import DarseQuran

/// Ported from Android's ui/manage/money/StudentFilterTest.kt (the search, pick and clear of the finance lists'
/// student filter, through its model), plus the filter string helpers it relies on.
@MainActor
final class StudentFilterTests: XCTestCase {
    private var server: StubServer!
    private let searched = Locked<String?>(nil)

    override func setUp() async throws {
        server = StubServer()
        let searched = self.searched
        server.handler = { request in
            searched.set(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value)
            return .json(#"{"data":[{"id":"s1","name":"Amina","email":"amina@example.test"}],"totalCount":1}"#)
        }
    }

    override func tearDown() async throws { CurrentEnvironment.testBaseUrl = nil; server = nil }

    func testSearchPickAndClear() async {
        var filter: String? = "courseId=c1"
        let model = MoneyStudentFilterModel(app: testContainer(server))
        model.type("ami")
        await waitUntil { model.matches.map(MoneyStudentFilterModel.label) == ["Amina (amina@example.test)"] }
        XCTAssertEqual("ami", searched.get)

        filter = model.pick(model.matches[0], filter: filter)
        XCTAssertEqual(["courseId": "c1", "studentId": "s1"], moneyDecodeFilters(filter))
        XCTAssertEqual("Amina (amina@example.test)", model.selectedLabel) // shown as "Student: Amina (amina@example.test)"

        filter = model.clear(filter: filter)
        XCTAssertEqual(["courseId": "c1"], moneyDecodeFilters(filter))
        XCTAssertNil(model.selectedLabel)
    }

    func testOneLetterDoesNotSearch() async {
        let model = MoneyStudentFilterModel(app: testContainer(server))
        model.type("a")
        await settle(for: .milliseconds(500))
        XCTAssertTrue(server.requests.isEmpty)
        XCTAssertTrue(model.matches.isEmpty)
    }

    func testFiltersRoundTrip() {
        let encoded = moneyWithFilters("tab=expenses", ["preset": "custom", "from": "2026-01-01", "q": "a b&c", "tab": nil])
        XCTAssertEqual(["preset": "custom", "from": "2026-01-01", "q": "a b&c"], moneyDecodeFilters(encoded))
        XCTAssertNil(moneyWithFilters("tab=expenses", ["tab": ""]))
        XCTAssertEqual([:], moneyDecodeFilters(nil))
    }
}
