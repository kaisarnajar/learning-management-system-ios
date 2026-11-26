import XCTest
@testable import DarseQuran

/// Ported from Android's LoaderViewModelTest (LoaderViewModel → Loader).
final class LoaderTests: XCTestCase {
    /// Fetches that wait until the test answers them.
    @MainActor
    private final class Answers {
        var pending: [CheckedContinuation<ApiResult<String>, Never>] = []
        func fetch() async -> ApiResult<String> { await withCheckedContinuation { pending.append($0) } }
    }

    @MainActor
    func testTheNewestLoadWins() async {
        let answers = Answers()
        let vm = Loader { await answers.fetch() }
        vm.reload() // a second load while the first is out
        await waitFor("both loads") { answers.pending.count == 2 }
        answers.pending[1].resume(returning: .success("new"))
        await waitFor("the new answer") { vm.state == .ready("new") }
        answers.pending[0].resume(returning: .success("old")) // the first answers late
        await settle()
        XCTAssertEqual(.ready("new"), vm.state)
    }

    @MainActor
    func testReloadKeepsContentUpWhileLoadStartsOver() async {
        var n = 0
        let vm = Loader<Int> { n += 1; return .success(n) }
        await waitFor("first load") { vm.state == .ready(1) }
        vm.reload()
        XCTAssertEqual(.ready(1), vm.state, "reload keeps the content up")
        await waitFor("reload") { vm.state == .ready(2) }
        vm.load()
        XCTAssertEqual(.loading, vm.state, "load starts over")
        await waitFor("load") { vm.state == .ready(3) }
    }
}
