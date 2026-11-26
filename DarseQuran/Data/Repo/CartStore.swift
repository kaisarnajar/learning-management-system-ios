import Foundation
import Observation

/// One holder at a time, for main-actor code that awaits in between (Kotlin's Mutex).
@MainActor
final class SerialLock {
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func lock() async {
        if locked { await withCheckedContinuation { waiters.append($0) } }
        locked = true
    }

    func unlock() {
        if waiters.isEmpty { locked = false } else { waiters.removeFirst().resume() }
    }

    func withLock<T>(_ block: () async -> T) async -> T {
        await lock()
        defer { unlock() }
        return await block()
    }
}

/// The signed-in student's server cart, shared by every bookstore screen (and the badge). Android's CartStore.
@MainActor
@Observable
final class CartStore {
    static let maxPerBook = 20

    private let repo: AcademyRepository
    private(set) var items: [CartItem] = []
    /// Books left out of the next checkout (the website's cart checkboxes); every book starts selected.
    private(set) var unselected: Set<String> = []

    /// What the server last confirmed; shown again if a change fails.
    @ObservationIgnored private var confirmed: [CartItem] = []
    @ObservationIgnored private let sending = SerialLock()
    @ObservationIgnored private var pending = 0
    /// The quantity each book should end up at, after every tap so far.
    @ObservationIgnored private var wishes: [String: Int] = [:]
    /// What was last sent for each book in the current burst of taps (used only while holding [sending]).
    @ObservationIgnored private var sent: [String: Int] = [:]
    /// Bumped by [clearLocal] (sign-out, another account): an answer to a request sent before it belongs to the
    /// previous cart and is dropped.
    @ObservationIgnored private var generation = 0

    init(repo: AcademyRepository) { self.repo = repo }

    @discardableResult
    func refresh() async -> ApiResult<[CartItem]> {
        let asked = generation
        let result = await repo.cart()
        if case .success(let lines) = result, asked == generation {
            confirmed = lines
            if pending == 0 { items = lines }
        }
        return result
    }

    /// Adds [delta] copies of a book (negative removes; reaching 0 takes the line out), capped at [maxPerBook].
    /// Returns an error message, or nil on success.
    ///
    /// Quick taps each count: the new quantity builds on every earlier tap and shows at once. Updates go to the server
    /// one at a time, each sending the newest quantity wanted. The server's answer is shown once no tap is waiting; a
    /// failure goes back to what the server last confirmed.
    func change(_ bookId: String, by delta: Int) async -> String? { await update(bookId) { $0 + delta } }

    /// Puts a book in the cart (one copy), or leaves it as it is if it is already there or on its way.
    func add(_ bookId: String) async -> String? { await update(bookId) { max($0, 1) } }

    private func update(_ bookId: String, to target: (Int) -> Int) async -> String? {
        let asked = generation
        let now = wishes[bookId] ?? quantityOf(bookId)
        let wanted = min(max(target(now), 0), CartStore.maxPerBook)
        if wanted == now { return nil }
        wishes[bookId] = wanted
        pending += 1
        items = items.withQuantity(bookId, wanted)

        return await sending.withLock {
            defer {
                pending -= 1
                if pending == 0 {
                    wishes.removeAll()
                    sent.removeAll()
                    if asked == generation { items = confirmed }
                }
            }
            guard let want = wishes[bookId] else { return nil } // an earlier failure reset it
            if sent[bookId] == want || asked != generation { return nil }
            let result = await repo.setCartLine(bookId: bookId, quantity: want)
            if asked != generation { return nil } // signed out meanwhile: not this cart any more
            switch result {
            case .success(let lines):
                sent[bookId] = want
                confirmed = lines
                return nil
            case .failure(let e):
                wishes.removeValue(forKey: bookId)
                items = confirmed
                return e.message
            }
        }
    }

    func select(_ bookId: String, _ selected: Bool) {
        if selected { unselected.remove(bookId) } else { unselected.insert(bookId) }
    }

    /// "Select all" / "Deselect all".
    func selectAll(_ selected: Bool) {
        unselected = selected ? [] : Set(items.map(\.bookId))
    }

    /// The cart lines that go to checkout.
    func selectedItems() -> [CartItem] { items.filter { !unselected.contains($0.bookId) } }

    /// The cart lines left out of checkout.
    func unselectedItems() -> [CartItem] { items.filter { unselected.contains($0.bookId) } }

    /// After an order: the server empties the whole cart, so the books that were left out of it ([left]) are put back,
    /// as the website keeps them in the cart. Everything is selected again. Returns how many couldn't be put back.
    func afterOrder(_ left: [CartLine]) async -> Int {
        let failed = await sending.withLock {
            var failed = 0
            for line in left {
                if case .failure = await repo.setCartLine(bookId: line.bookId, quantity: line.quantity) { failed += 1 }
            }
            return failed
        }
        unselected = []
        await refresh()
        return failed
    }

    func quantityOf(_ bookId: String) -> Int { items.first { $0.bookId == bookId }?.quantity ?? 0 }

    var count: Int { items.reduce(0) { $0 + $1.quantity } }

    func clearLocal() {
        generation += 1
        wishes.removeAll()
        confirmed = []
        items = []
        unselected = []
    }
}

private extension Array where Element == CartItem {
    /// A book not in the cart yet appears once the server answers (it sends the title, price and cover).
    func withQuantity(_ bookId: String, _ quantity: Int) -> [CartItem] {
        if quantity == 0 { return filter { $0.bookId != bookId } }
        return map { item in
            guard item.bookId == bookId else { return item }
            var copy = item
            copy.quantity = quantity
            return copy
        }
    }
}
