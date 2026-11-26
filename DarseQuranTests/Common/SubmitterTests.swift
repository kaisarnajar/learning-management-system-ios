import XCTest
@testable import DarseQuran

/// Ported from Android's SubmitViewModelTest (SubmitViewModel → Submitter).
final class SubmitterTests: XCTestCase {
    @MainActor
    func testTwoTapsInOneFrameSendOnce() async {
        let vm = Submitter()
        var sends = 0
        vm.submit { sends += 1; return SubmitResult(message: "Password changed.", ok: true) }
        vm.submit { sends += 1; return SubmitResult(message: "Password changed.", ok: true) }
        await waitFor("the result") { vm.result != nil }
        await settle()
        XCTAssertEqual(1, sends)
        XCTAssertEqual(SubmitResult(message: "Password changed.", ok: true), vm.result)
    }

    @MainActor
    func testBusyWhileSendingAndClearedAfter() async {
        let vm = Submitter()
        var gate: CheckedContinuation<Void, Never>?
        vm.submit {
            await withCheckedContinuation { gate = $0 }
            return SubmitResult(message: "Wrong password.", ok: false)
        }
        XCTAssertTrue(vm.busy)
        await waitFor("the request to start") { gate != nil }
        XCTAssertTrue(vm.busy)
        XCTAssertNil(vm.result)
        gate?.resume()
        await waitFor("the request to finish") { !vm.busy }
        XCTAssertEqual(SubmitResult(message: "Wrong password.", ok: false), vm.result)
    }
}
