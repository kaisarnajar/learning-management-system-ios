import Observation
import SwiftUI

/// Loading → content or error, for screens that load one thing (Android's Load).
enum Load<T> {
    case loading
    case ready(T)
    case failed(String)

    var value: T? { if case .ready(let v) = self { v } else { nil } }
    var isLoading: Bool { if case .loading = self { true } else { false } }
}

extension Load: Equatable where T: Equatable {}

extension Result where Failure == ApiError {
    func toLoad() -> Load<Success> {
        switch self {
        case .success(let v): .ready(v)
        case .failure(let e): .failed(e.message)
        }
    }
}

/// Loads one thing (a record, a list) for a screen (Android's LoaderViewModel). [reload] refreshes in place (the current
/// content stays up until the new one arrives); [load] starts over from the loading state. The newest load wins, so an
/// older answer that arrives late can't replace a newer one.
@MainActor
@Observable
final class Loader<T> {
    private(set) var state: Load<T> = .loading
    @ObservationIgnored private let fetch: () async -> ApiResult<T>
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(_ fetch: @escaping () async -> ApiResult<T>) {
        self.fetch = fetch
        reload()
    }

    @discardableResult
    func reload(showLoading: Bool = false) -> Task<Void, Never> {
        task?.cancel()
        generation += 1
        let gen = generation
        if showLoading || state.value == nil { state = .loading }
        let t = Task { [weak self] in
            guard let self else { return }
            let result = await self.fetch()
            guard gen == self.generation, !(result.error?.cancelled ?? false) else { return }
            self.state = result.toLoad()
        }
        task = t
        return t
    }

    @discardableResult
    func load() -> Task<Void, Never> { reload(showLoading: true) }

    /// Replaces the content shown (after an edit made on this screen).
    func set(_ value: T) { state = .ready(value) }

    /// Pull to refresh: waits for the reload.
    func refresh() async { await reload().value }
}

/// What a submitted form says back: the message to show, and whether it worked.
struct SubmitResult: Equatable {
    let message: String
    let ok: Bool
}

/// Sends a one-off form (change password, delete account, contact): one request at a time, and the outcome kept
/// (Android's SubmitViewModel). [busy] is set before the request starts, so a second tap does nothing.
@MainActor
@Observable
final class Submitter {
    private(set) var busy = false
    var result: SubmitResult?

    func submit(_ send: @escaping () async -> SubmitResult) {
        if busy { return }
        busy = true
        result = nil
        Task {
            let r = await send()
            result = r
            busy = false
        }
    }
}

/// Calls [reload] when the user comes back to this screen (from a screen pushed on top of it, or from another app), so
/// things like a just-submitted payment show up without a manual pull-to-refresh (Android's ReloadOnReturn).
struct ReloadOnReturn: ViewModifier {
    let reload: () -> Void
    @State private var appeared = false
    @State private var away = false
    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        content
            .onAppear {
                if appeared, away { away = false; reload() }
                appeared = true
            }
            .onDisappear { away = true }
            .onChange(of: phase) { _, new in
                if new == .background { away = true }
                if new == .active, away, appeared { away = false; reload() }
            }
    }
}

extension View {
    func reloadOnReturn(_ reload: @escaping () -> Void) -> some View { modifier(ReloadOnReturn(reload: reload)) }
}

// MARK: - paged lists (PagedList.kt)

struct PagedState<T: Model> {
    var items: [T] = []
    var page = 0
    var total = 0
    var loading = true
    var refreshing = false
    var error: String? = nil
    var query = ""
    var filter: String? = nil

    var canLoadMore: Bool { !loading && items.count < total }
}

/// A searchable, paginated list backed by one /api/v1 list endpoint (Android's PagedViewModel).
///
/// A refresh, search or filter change supersedes whatever is loading: the old request is cancelled and, should its
/// answer still arrive, ignored (a late page of the previous query must not be appended to the new one). Only one
/// "load more" runs at a time.
@MainActor
@Observable
final class PagedListModel<T: Model> {
    private(set) var state = PagedState<T>()
    @ObservationIgnored private let fetch: (Int, String, String?) async -> ApiResult<Paged<T>>
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    /// The search and filter the items on show were loaded for.
    @ObservationIgnored private var shownFor: (String, String?) = ("", nil)
    /// The last load that failed was a reset (refresh, search or filter change), not a further page.
    @ObservationIgnored private var resetFailed = false

    init(filter: String? = nil, _ fetch: @escaping (_ page: Int, _ query: String, _ filter: String?) async -> ApiResult<Paged<T>>) {
        self.fetch = fetch
        state.filter = filter
        shownFor = ("", filter)
        load(reset: true)
    }

    func refresh() { state.refreshing = true; load(reset: true) }

    /// Pull to refresh: waits until the first page is back.
    func refreshAndWait() async {
        refresh()
        await task?.value
    }

    func search(_ query: String) { state.query = query; load(reset: true) }
    func filter(_ value: String?) { state.filter = value; load(reset: true) }
    func loadMore() { if state.canLoadMore, task == nil { load(reset: false) } }

    /// The list footer's Retry: repeats what failed (after a failed search or filter, from the first page).
    func retry() { if resetFailed { load(reset: true) } else { loadMore() } }

    /// Changes one loaded item in place (after an edit made from the list).
    func update(_ transform: ([T]) -> [T]) { state.items = transform(state.items) }

    private func load(reset: Bool) {
        if reset { task?.cancel(); task = nil; generation += 1 }
        let gen = generation
        let current = state
        let page = reset ? 1 : current.page + 1
        state.loading = true
        state.error = nil
        task = Task { [weak self] in
            guard let self else { return }
            let r = await self.fetch(page, current.query, current.filter)
            guard gen == self.generation, !(r.error?.cancelled ?? false) else { return } // superseded while in flight
            self.task = nil
            self.resetFailed = reset && !r.isOk
            switch r {
            case .success(let paged):
                if reset { self.shownFor = (current.query, current.filter) }
                self.state.items = reset ? paged.data : self.state.items + paged.data
                self.state.page = page
                self.state.total = paged.totalCount
                self.state.loading = false
                self.state.refreshing = false
            case .failure(let e):
                // A failed refresh keeps the list; a failed search or filter change must not show the old results.
                let stale = reset && (self.shownFor.0 != current.query || self.shownFor.1 != current.filter)
                self.state.loading = false
                self.state.refreshing = false
                self.state.error = e.message
                if stale { self.state.items = []; self.state.page = 0; self.state.total = 0 }
            }
        }
    }
}

/// [items] without repeated keys. Pages are fetched by offset, so a row added on the server between two pages shows up
/// again at the top of the next one.
func distinctByKey<T, K: Hashable>(_ items: [T], _ key: (T) -> K) -> [(K, T)] {
    var seen = Set<K>()
    return items.compactMap { item in
        let k = key(item)
        return seen.insert(k).inserted ? (k, item) : nil
    }
}

/// Standard list screen body: pull to refresh, search, infinite scroll, empty and error states (Android's PagedListBody).
struct PagedListBody<T: Model, K: Hashable, Header: View, Row: View>: View {
    let model: PagedListModel<T>
    var searchHint: String?
    let emptyTitle: String
    let key: (T) -> K
    var spacing: CGFloat = 12
    @ViewBuilder var header: () -> Header
    @ViewBuilder var row: (T) -> Row

    init(
        _ model: PagedListModel<T>, searchHint: String?, emptyTitle: String, key: @escaping (T) -> K, spacing: CGFloat = 12,
        @ViewBuilder header: @escaping () -> Header = { EmptyView() }, @ViewBuilder row: @escaping (T) -> Row
    ) {
        self.model = model
        self.searchHint = searchHint
        self.emptyTitle = emptyTitle
        self.key = key
        self.spacing = spacing
        self.header = header
        self.row = row
    }

    var body: some View {
        let state = model.state
        ScrollView {
            LazyVStack(spacing: spacing) {
                if let searchHint { SearchField(initial: state.query, placeholder: searchHint) { model.search($0) } }
                header()
                if let error = state.error, state.items.isEmpty {
                    ErrorState(message: error) { model.refresh() }
                } else if !state.loading, state.items.isEmpty {
                    EmptyState(title: emptyTitle, message: state.query.trimmed.isEmpty ? nil : "Try a different search.")
                }
                let rows = distinctByKey(state.items, key)
                ForEach(rows, id: \.0) { pair in
                    row(pair.1)
                        .onAppear {
                            // Near the end: ask for the next page (not after a failed page; that waits for Retry).
                            if state.error == nil, rows.suffix(3).contains(where: { $0.0 == pair.0 }) { model.loadMore() }
                        }
                }
                if let error = state.error, !state.items.isEmpty { LoadMoreError(message: error) { model.retry() } }
                if state.loading, !state.refreshing {
                    if state.items.isEmpty { SkeletonList(rows: 4).padding(-Spacing.screen) } else { LoadingBox(height: 72) }
                }
            }
            .padding(Spacing.screen)
        }
        .refreshable { await model.refreshAndWait() }
        .background(Scheme.background)
    }
}

/// The footer of a list whose next page failed to load.
struct LoadMoreError: View {
    let message: String
    let onRetry: () -> Void
    var body: some View {
        HStack {
            Text(message).textStyle(Typo.bodySmall).foregroundStyle(Scheme.error).frame(maxWidth: .infinity, alignment: .leading)
            TextButton("Retry", action: onRetry)
        }
        .padding(.vertical, 4)
    }
}

/// Builds a screen's model once, from the app container in the environment, and keeps it for the screen's lifetime
/// (Android's viewModel(factory = vmFactory { ... })).
///
///     var body: some View { WithModel({ HomeModel(app: $0) }) { model in HomeContent(model: model) } }
struct WithModel<M: AnyObject, Content: View>: View {
    let make: @MainActor (AppContainer) -> M
    @ViewBuilder let content: (M) -> Content
    @Environment(AppContainer.self) private var app
    @State private var model: M?

    init(_ make: @escaping @MainActor (AppContainer) -> M, @ViewBuilder content: @escaping (M) -> Content) {
        self.make = make
        self.content = content
    }

    var body: some View {
        if let model {
            content(model)
        } else {
            Scheme.background.ignoresSafeArea().onAppear { model = make(app) }
        }
    }
}
