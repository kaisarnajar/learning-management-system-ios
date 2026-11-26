import XCTest
@testable import DarseQuran

/// Ported from Android's CartStoreTest.
@MainActor
final class CartStoreTests: XCTestCase {
    private struct Backend {
        var sent: [Int] = []
        var failNext = false
        var afterSignOut = false
    }

    private var server: StubServer!
    private var container: AppContainer!
    private let backend = Locked(Backend())
    private var cart: CartStore { container.cart }

    private nonisolated static func items(_ quantity: Int) -> String {
        quantity == 0 ? #"{"items":[]}"# : #"{"items":[{"bookId":"b1","title":"Riyad as-Salihin","quantity":\#(quantity)}]}"#
    }

    override func setUp() async throws {
        server = StubServer()
        let backend = self.backend
        server.handler = { request in
            switch request.method {
            case "GET":
                return .json(backend.get.afterSignOut ? #"{"items":[]}"# : Self.items(1))
            case "PATCH":
                let body = request.text
                let quantity = body.firstMatch(of: /"quantity":(\d+)/).map { Int($0.1)! } ?? -1
                backend.update { $0.sent.append(quantity) }
                if body.contains(#""b2""#) { return .json(#"{"error":"Only 0 in stock."}"#, status: 409) }
                let fail = backend.update { b -> Bool in
                    defer { b.failNext = false }
                    return b.failNext
                }
                if fail { return .json(#"{"error":"Only 2 in stock."}"#, status: 409) }
                Thread.sleep(forTimeInterval: 0.08) // the server takes a moment
                return .json(Self.items(quantity))
            default:
                return .json("{}", status: 404)
            }
        }
        container = testContainer(server)
        // A cart belongs to a signed-in student: signing in fetches it (one copy of b1).
        container.sessionStore.save(studentTokens)
        await waitUntil(5, "the cart") { container.cart.quantityOf("b1") == 1 }
    }

    override func tearDown() async throws {
        container.sessionStore.clear()
        CurrentEnvironment.testBaseUrl = nil
        container = nil
        server = nil
    }

    func testQuickTapsAllCount() async {
        let cart = self.cart
        async let a = cart.change("b1", by: 1)
        async let b = cart.change("b1", by: 1)
        async let c = cart.change("b1", by: 1)
        _ = await (a, b, c)
        let sent = backend.get.sent
        // Taps made while an update is on its way are merged into the next one; nothing is lost or reordered.
        XCTAssertEqual(sent.last, 4)
        XCTAssertEqual(Array(Set(sent)).sorted(), sent)
        XCTAssertEqual(cart.quantityOf("b1"), 4)
    }

    func testARejectedChangeGoesBackToWhatTheServerHas() async {
        backend.update { $0.failNext = true }
        let error = await cart.change("b1", by: 1)
        XCTAssertNotNil(error)
        XCTAssertEqual(cart.quantityOf("b1"), 1)
    }

    func testTheCapIsEnforcedHere() async {
        _ = await cart.change("b1", by: 50)
        XCTAssertEqual(backend.get.sent, [CartStore.maxPerBook])
    }

    func testGoingToZeroRemovesTheLine() async {
        _ = await cart.change("b1", by: -1)
        XCTAssertEqual(cart.quantityOf("b1"), 0)
        XCTAssertEqual(cart.items, [])
    }

    func testTwoTapsOnAddToCartAddOneCopy() async {
        _ = await cart.change("b1", by: -1) // start without the book
        backend.update { $0.sent = [] }
        let cart = self.cart
        async let a = cart.add("b1")
        async let b = cart.add("b1")
        _ = await (a, b)
        XCTAssertEqual(backend.get.sent, [1])
        XCTAssertEqual(cart.quantityOf("b1"), 1)
    }

    func testBooksThatCouldNotBePutBackAfterAnOrderAreCounted() async {
        let failed = await cart.afterOrder([CartLine(bookId: "b1", quantity: 2), CartLine(bookId: "b2", quantity: 1)])
        XCTAssertEqual(failed, 1)
    }

    func testSigningOutDuringAChangeDoesNotBringTheOldCartBack() async throws {
        let cart = self.cart
        let change = Task { await cart.change("b1", by: 1) } // answered after 80 ms
        try await Task.sleep(for: .milliseconds(20))
        backend.update { $0.afterSignOut = true }
        container.sessionStore.clear()
        await waitUntil(5, "an empty cart") { cart.items.isEmpty }
        _ = await change.value
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(cart.items, [])
    }
}

/// Ported from Android's CartSessionTest: the cart follows the session with no bookstore screen open.
@MainActor
final class CartSessionTests: XCTestCase {
    func testSigningInFetchesTheCartAndSigningOutEmptiesIt() async {
        let server = StubServer()
        server.handler = { _ in .json(#"{"items":[{"bookId":"b1","title":"Riyad as-Salihin","quantity":2}]}"#) }
        let container = testContainer(server)
        defer { CurrentEnvironment.testBaseUrl = nil }
        container.sessionStore.save(studentTokens)
        await waitUntil(5, "two copies") { container.cart.quantityOf("b1") == 2 }
        container.sessionStore.clear()
        await waitUntil(5, "an empty cart") { container.cart.quantityOf("b1") == 0 }
        XCTAssertEqual(container.cart.items, [])
    }
}
