import XCTest
@testable import DarseQuran

/// Ported from Android's PagedViewModelTest and LoadMoreTest (PagedViewModel → PagedListModel).
final class PagedListModelTests: XCTestCase {
    /// Every fetch waits until the test answers it.
    @MainActor
    private final class Requests {
        struct Call {
            let page: Int
            let query: String
            let filter: String?
            let answer: CheckedContinuation<ApiResult<Paged<String>>, Never>
        }
        var calls: [Call] = []

        func fetch(_ page: Int, _ query: String, _ filter: String?) async -> ApiResult<Paged<String>> {
            await withCheckedContinuation { calls.append(Call(page: page, query: query, filter: filter, answer: $0)) }
        }
    }

    @MainActor
    private func model(_ r: Requests) -> PagedListModel<String> {
        PagedListModel { page, query, filter in await r.fetch(page, query, filter) }
    }

    /// Waits for call [index] to be made, then answers it.
    @MainActor
    private func answer(_ r: Requests, _ index: Int, _ items: String..., total: Int = 100) async {
        await waitFor("call \(index)") { r.calls.count > index }
        let call = r.calls[index]
        call.answer.resume(returning: .success(Paged(data: items, totalCount: total, page: call.page, pageSize: items.count)))
        await settle(for: .milliseconds(20))
    }

    @MainActor
    private func fail(_ r: Requests, _ index: Int) async {
        await waitFor("call \(index)") { r.calls.count > index }
        r.calls[index].answer.resume(returning: .failure(ApiError(message: "No connection.")))
        await settle(for: .milliseconds(20))
    }

    @MainActor
    func testALatePageOfTheOldQueryIsNotAppendedToTheNewOne() async {
        let r = Requests()
        let vm = model(r)
        await answer(r, 0, "a1", "a2")
        vm.loadMore()                          // page 2 of "" in flight
        await waitFor("page 2") { r.calls.count == 2 }
        vm.search("fiqh")                      // page 1 of "fiqh" in flight
        await answer(r, 2, "f1")               // the new query answers first
        await answer(r, 1, "a3", "a4")         // then the stale page 2 arrives
        XCTAssertEqual(["f1"], vm.state.items)
        XCTAssertEqual(1, vm.state.page)
        XCTAssertEqual("fiqh", r.calls[2].query)
    }

    @MainActor
    func testARefreshDuringLoadMoreEndsOnPageOne() async {
        let r = Requests()
        let vm = model(r)
        await answer(r, 0, "a1", "a2")
        vm.loadMore()
        await waitFor("page 2") { r.calls.count == 2 }
        vm.refresh()
        await answer(r, 1, "a3")               // stale page 2
        await answer(r, 2, "b1", "b2")
        XCTAssertEqual(["b1", "b2"], vm.state.items)
        XCTAssertEqual(1, vm.state.page)
        XCTAssertFalse(vm.state.refreshing)
    }

    @MainActor
    func testLoadMoreRunsOneAtATime() async {
        let r = Requests()
        let vm = model(r)
        await answer(r, 0, "a1")
        vm.loadMore(); vm.loadMore(); vm.loadMore()
        await settle()
        XCTAssertEqual(2, r.calls.count)
        await answer(r, 1, "a2")
        XCTAssertEqual(["a1", "a2"], vm.state.items)
    }

    @MainActor
    func testAFilterChangeWinsOverTheOldFilter() async {
        let r = Requests()
        let vm = model(r)
        vm.filter("unread")
        await answer(r, 1, "u1")
        await answer(r, 0, "x1", "x2")         // the initial unfiltered load answers last
        XCTAssertEqual(["u1"], vm.state.items)
        XCTAssertEqual("unread", vm.state.filter)
    }

    @MainActor
    func testAFailedFilterChangeDoesNotShowTheOldListAndRetryStartsFromPageOne() async {
        let r = Requests()
        let vm = model(r)
        await answer(r, 0, "x1", "x2")
        vm.filter("unread")
        await fail(r, 1)
        XCTAssertEqual([], vm.state.items)
        XCTAssertEqual("No connection.", vm.state.error)
        vm.retry()
        await waitFor("the retry") { r.calls.count == 3 }
        XCTAssertEqual(1, r.calls[2].page)
        XCTAssertEqual("unread", r.calls[2].filter)
        await answer(r, 2, "u1")
        XCTAssertEqual(["u1"], vm.state.items)
    }

    @MainActor
    func testAFailedRefreshKeepsTheListAndAFailedPageIsRetried() async {
        let r = Requests()
        let vm = model(r)
        await answer(r, 0, "a1")
        vm.refresh()
        await fail(r, 1)
        XCTAssertEqual(["a1"], vm.state.items)
        vm.retry()
        await waitFor("the retry") { r.calls.count == 3 }
        XCTAssertEqual(1, r.calls[2].page)
        await answer(r, 2, "a1")
        vm.loadMore()
        await fail(r, 3)
        vm.retry()
        await waitFor("the page retry") { r.calls.count == 5 }
        XCTAssertEqual(2, r.calls[4].page)
    }

    func testRepeatedKeysAreDroppedForDisplay() {
        XCTAssertEqual(["a", "b", "c"], distinctByKey(["a", "b", "b", "c", "a"]) { $0 }.map(\.1))
    }

    // MARK: LoadMoreTest

    /// Android's LoadMoreTest drives PagedListBody in Compose; the list view's "near the end" trigger is SwiftUI here,
    /// so this checks the model side: a failed page keeps the list and shows the error, and Retry loads that page.
    @MainActor
    func testAFailedPageShowsRetryAndRetryLoadsIt() async {
        var pages: [Int] = []
        var failPageTwo = true
        let vm = PagedListModel<String> { page, _, _ in
            pages.append(page)
            if page == 1 { return .success(Paged(data: ["Item 1"], totalCount: 2, page: 1, pageSize: 1)) }
            if failPageTwo { return .failure(ApiError(message: "No connection.")) }
            return .success(Paged(data: ["Item 2"], totalCount: 2, page: 2, pageSize: 1))
        }
        await waitFor("page 1") { vm.state.items == ["Item 1"] }
        vm.loadMore()
        await waitFor("the failed page") { vm.state.error != nil }
        XCTAssertEqual("No connection.", vm.state.error)
        XCTAssertEqual(["Item 1"], vm.state.items)
        await settle()
        XCTAssertEqual([1, 2], pages, "no automatic retry loop")

        failPageTwo = false
        vm.retry()
        await waitFor("page 2") { vm.state.items == ["Item 1", "Item 2"] }
        XCTAssertEqual([1, 2, 2], pages)
        XCTAssertNil(vm.state.error)
    }
}
