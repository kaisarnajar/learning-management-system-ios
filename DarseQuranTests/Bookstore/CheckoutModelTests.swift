import XCTest
@testable import DarseQuran

/// Ported from Android's CheckoutViewModelTest.
@MainActor
final class CheckoutModelTests: XCTestCase {
    private struct Backend {
        var orders: [String] = []
        var cartPatches: [String] = []
        var cartQuantity = 1
        var secondBook = false
    }

    private var server: StubServer!
    private var container: AppContainer!
    private let backend = Locked(Backend())

    override func setUp() async throws {
        server = StubServer()
        let backend = self.backend
        server.handler = { request in
            switch request.path {
            case "/api/v1/bookstore/cart":
                if request.method == "PATCH" { backend.update { $0.cartPatches.append(request.text) } }
                return .json(Self.cartBody(backend.get))
            case "/api/v1/bookstore/checkout-quote":
                return .json(#"{"lines":[],"totalAmountInrPaise":\#(backend.get.cartQuantity * 40000)}"#)
            case "/api/v1/bookstore/orders":
                backend.update { $0.orders.append(request.text) }
                return .json(#"{"success":true}"#)
            default:
                return .json("{}", status: 404)
            }
        }
        container = testContainer(server)
        container.sessionStore.save(studentTokens)
        await waitUntil(5, "the cart") { container.cart.quantityOf("b1") == 1 }
    }

    private nonisolated static func cartBody(_ b: Backend) -> String {
        let b1 = #"{"bookId":"b1","title":"Riyad as-Salihin","quantity":\#(b.cartQuantity)}"#
        let b2 = #"{"bookId":"b2","title":"Bulugh al-Maram","quantity":2}"#
        return #"{"items":[\#(b1)\#(b.secondBook ? ",\(b2)" : "")]}"#
    }

    override func tearDown() async throws {
        container.sessionStore.clear()
        // The container empties the cart (and its selection) when it sees the sign-out.
        await waitUntil(5, "an empty cart") { container.cart.items.isEmpty }
        CurrentEnvironment.testBaseUrl = nil
        container = nil
        server = nil
    }

    private func model() -> CheckoutModel { CheckoutModel(repo: container.repo, cart: container.cart) }

    private func quoteReady(_ vm: CheckoutModel) async {
        await waitUntil(5, "the quote") { vm.state.quote.value != nil }
    }

    private func place(_ vm: CheckoutModel) {
        vm.place(method: "upi", reference: "412788901234", address: "House 1, Srinagar", pin: "190001", phone: "9999999999", screenshot: nil)
    }

    func testTheQuotedCartIsOrdered() async {
        let vm = model()
        await quoteReady(vm)
        place(vm)
        await waitUntil(5, "done") { vm.state.done }
        let orders = backend.get.orders
        XCTAssertEqual(orders.count, 1)
        XCTAssertTrue(orders[0].contains(#"{"bookId":"b1","quantity":1}"#), orders[0])
    }

    func testACartChangedAfterTheQuoteIsNotOrdered() async throws {
        let vm = model()
        await quoteReady(vm)
        backend.update { $0.cartQuantity = 2 }
        await container.cart.refresh() // e.g. changed on the website meanwhile
        place(vm)
        await waitUntil(5, "the error") { vm.state.error != nil }
        await waitUntil(5, "the new total") { vm.state.quote.value?.totalAmountInrPaise == 80000 }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(backend.get.orders.count, 0)
    }

    func testTheOrderCarriesTheTotalShown() async {
        let vm = model()
        await quoteReady(vm)
        place(vm)
        await waitUntil(5, "done") { vm.state.done }
        let order = backend.get.orders[0]
        XCTAssertTrue(order.contains("expectedTotalPaise"), order)
        XCTAssertTrue(order.contains("40000"), order)
        XCTAssertFalse(order.contains("notes"), order)
    }

    func testOnlyTheSelectedBooksAreOrderedAndTheRestStayInTheCart() async throws {
        backend.update { $0.secondBook = true }
        await container.cart.refresh()
        container.cart.select("b2", false)
        let vm = model()
        await quoteReady(vm)
        place(vm)
        await waitUntil(5, "done") { vm.state.done }
        // The book id with its key: the multipart boundary is random and may contain "b2" by chance.
        XCTAssertFalse(backend.get.orders[0].contains(#""bookId":"b2""#), backend.get.orders[0])
        let patches = try backend.get.cartPatches.map { try JSONDecoder().decode(CartLine.self, from: Data($0.utf8)) }
        XCTAssertEqual(patches, [CartLine(bookId: "b2", quantity: 2)])
        XCTAssertTrue(container.cart.unselected.isEmpty)
    }
}
