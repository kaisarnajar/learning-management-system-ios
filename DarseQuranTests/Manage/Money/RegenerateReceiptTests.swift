import XCTest
@testable import DarseQuran

/// Ported from Android's ui/manage/money/RegenerateReceiptTest.kt.
@MainActor
final class RegenerateReceiptTests: XCTestCase {
    private var server: StubServer!

    override func setUp() async throws { server = StubServer() }
    override func tearDown() async throws { CurrentEnvironment.testBaseUrl = nil; server = nil }

    /// Answers the requests in order with [responses] (Android's MockWebServer.enqueue).
    private func enqueue(_ responses: [StubServer.Response]) {
        let queue = Locked(responses)
        server.handler = { _ in queue.update { $0.isEmpty ? .json("{}", status: 500) : $0.removeFirst() } }
    }

    func testBothStepsWorking() async throws {
        enqueue([.json(#"{"success":true}"#), .json(#"{"success":true}"#)])
        let failure = try await testContainer(server).regenerateReceipt("p1")
        XCTAssertNil(failure)
        XCTAssertEqual(["DELETE", "POST"], server.requests.map(\.method))
        XCTAssertEqual(["/api/v1/admin/receipts/p1", "/api/v1/admin/receipts/p1"], server.requests.map(\.path))
    }

    func testGenerateFailingAfterTheDeleteIsReported() async throws {
        enqueue([.json(#"{"success":true}"#), .json(#"{"error":"PDF service unavailable."}"#, status: 500)])
        let failure = try await testContainer(server).regenerateReceipt("p1")
        XCTAssertEqual("PDF service unavailable.", failure)
    }

    func testAFailedDeleteChangesNothingAndThrows() async {
        enqueue([.json(#"{"error":"Forbidden"}"#, status: 403)])
        do {
            _ = try await testContainer(server).regenerateReceipt("p1")
            XCTFail("expected the delete's failure")
        } catch {
            XCTAssertTrue(error is HTTPError, "\(error)")
        }
        XCTAssertEqual(1, server.requests.count)
    }
}
