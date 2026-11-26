import XCTest
@testable import DarseQuran

/// Ported from Android's ui/manage/common/ActionRunnerTest.kt.
@MainActor
final class ActionRunnerTests: XCTestCase {
    private var server: StubServer!

    override func setUp() async throws { server = StubServer() }
    override func tearDown() async throws { CurrentEnvironment.testBaseUrl = nil; server = nil }

    func testTwoTapsInOneFrameWriteOnce() async {
        let runner = ActionRunner(app: testContainer(server))
        var writes = 0
        // Both taps happen before the first write starts.
        runner.run({ _ in writes += 1 })
        runner.run({ _ in writes += 1 })
        await waitUntil { !runner.busy }
        XCTAssertEqual(1, writes)
    }

    func testAWriteFinishesAndReportsAfterItsScreenIsGone() async {
        let app = testContainer(server)
        var runner: ActionRunner? = ActionRunner(app: app)
        let gate = AsyncStream<Void>.makeStream()
        runner?.run({ _ in for await _ in gate.stream { break } }, success: "Payment recorded.")
        runner = nil // the screen closes while the write is in flight
        gate.continuation.yield()
        await waitUntil { app.toaster.message == "Payment recorded." }
    }

    func testAFailedWriteShowsTheServersMessage() async {
        server.handler = { _ in .json(#"{"error":"Amount is required."}"#, status: 400) }
        let app = testContainer(server)
        let runner = ActionRunner(app: app)
        var succeeded = false
        runner.run({ try await $0.service(MoneyAPI.self).recordPayment(formOf { _ in }) }, success: "Saved.") { _ in succeeded = true }
        await waitUntil { app.toaster.message != nil }
        XCTAssertEqual("Amount is required.", app.toaster.message)
        XCTAssertFalse(succeeded)
    }
}
