import Foundation
import Observation

// MARK: - words (CartScreen.kt)

/// The website's book status words (services/bookstore.ts bookStatusLabel).
func bookStatusLabel(_ status: String) -> String {
    switch status {
    case "AVAILABLE": "Available"
    case "OUT_OF_STOCK": "Out of Stock"
    case "COMING_SOON": "Coming Soon"
    default: status
    }
}

/// "1 item", "3 items", as the website counts the cart.
func itemCount(_ count: Int) -> String { "\(count) item\(count != 1 ? "s" : "")" }

/// What the cart's checkout button offers, as on the website's cart page.
enum CartCheckout { case verifyEmail, nothingSelected, ready }

/// The website blocks checkout until the e-mail is verified; [emailVerified] is nil while unknown (the server refuses
/// the order anyway).
func cartCheckout(emailVerified: Bool?, selectedCount: Int) -> CartCheckout {
    if emailVerified == false { return .verifyEmail }
    if selectedCount == 0 { return .nothingSelected }
    return .ready
}

/// Said after an order when some of the books left out of it couldn't be put back in the cart.
func notRestoredNote(_ count: Int) -> String {
    switch count {
    case 0: ""
    case 1: "\n\nOne book you left out of this order couldn't be put back in your cart. Please add it again."
    default: "\n\n\(count) books you left out of this order couldn't be put back in your cart. Please add them again."
    }
}

/// "Order #A1B2C3": the last six characters of the id.
func orderNumber(_ id: String) -> String { "Order #\(id.suffix(6).uppercased())" }

// MARK: - cart (Android's CartViewModel)

@MainActor
@Observable
final class CartModel {
    let cart: CartStore
    @ObservationIgnored private let auth: AuthRepository
    var message: String?
    /// Whether the account's e-mail is verified (nil until known): the website's cart blocks checkout without.
    private(set) var emailVerified: Bool?

    init(cart: CartStore, auth: AuthRepository) {
        self.cart = cart
        self.auth = auth
        // Signing in and out is handled by AppContainer; opening a bookstore screen just catches up with changes made
        // elsewhere (e.g. on the website).
        if auth.sessionStore.current != nil { Task { await cart.refresh() } }
    }

    func change(_ bookId: String, by delta: Int) { Task { message = await cart.change(bookId, by: delta) } }
    func add(_ bookId: String) { Task { message = await cart.add(bookId) } }

    func checkEmail() {
        let auth = self.auth
        Task {
            if case .success(let p) = await auth.profile() { emailVerified = p.emailVerified != nil }
        }
    }
}

// MARK: - checkout (Android's CheckoutViewModel)

struct CheckoutState {
    var quote: Load<CheckoutQuote> = .loading
    var settings: PaymentSettings? = nil
    var settingsError: String? = nil
    var submitting = false
    var error: String? = nil
    var done = false
    /// Books left out of the order that couldn't be put back in the cart afterwards.
    var notRestored = 0
}

@MainActor
@Observable
final class CheckoutModel {
    private(set) var state = CheckoutState()
    @ObservationIgnored private let repo: AcademyRepository
    @ObservationIgnored private let cart: CartStore
    /// The lines the shown total was worked out for: the order is placed for exactly these.
    @ObservationIgnored private var quotedLines: [CartLine] = []
    @ObservationIgnored private var quotedTotal = 0

    init(repo: AcademyRepository, cart: CartStore) {
        self.repo = repo
        self.cart = cart
        load()
    }

    /// The lines picked on the cart page.
    private var lines: [CartLine] { cart.selectedItems().map { CartLine(bookId: $0.bookId, quantity: $0.quantity) } }

    @discardableResult
    func load() -> Task<Void, Never> {
        state.quote = .loading
        let repo = self.repo
        return Task {
            let settings = await repo.paymentSettings()
            let asked = lines
            let quote = await repo.checkoutQuote(asked)
            if case .success(let q) = quote {
                quotedLines = asked
                quotedTotal = q.totalAmountInrPaise
            }
            state.quote = quote.toLoad()
            state.settings = settings.value
            state.settingsError = settings.error?.message
        }
    }

    /// Fetches the academy's UPI and bank details again (after they failed to load).
    func reloadSettings() {
        state.settingsError = nil
        let repo = self.repo
        Task {
            let r = await repo.paymentSettings()
            state.settings = r.value ?? state.settings
            state.settingsError = r.error?.message
        }
    }

    /// One order per checkout: a second tap (even in the same frame) or a tap after success is ignored.
    @discardableResult
    func place(method: String, reference: String, address: String, pin: String, phone: String, screenshot: (Data, String)?) -> Task<Void, Never>? {
        if state.submitting || state.done { return nil }
        // The student paid the total shown for the quoted cart; if the cart has changed since (another screen, a
        // refresh), placing it would order something other than what was paid for.
        if Set(lines) != Set(quotedLines) {
            state.error = "Your cart changed since this total was worked out. Check the new total below before paying."
            load()
            return nil
        }
        state.submitting = true
        state.error = nil
        let left = cart.unselectedItems().map { CartLine(bookId: $0.bookId, quantity: $0.quantity) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let items = (try? encoder.encode(quotedLines)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let fields: [(String, String)] = [
            ("items", items),
            ("paymentMethod", method),
            ("upiTransactionId", reference.trimmed),
            ("deliveryAddress", address.trimmed),
            ("deliveryPinCode", pin.trimmed),
            ("deliveryPhoneNumber", phone.trimmed),
            // The total shown; the server refuses the order if it has changed since.
            ("expectedTotalPaise", String(quotedTotal)),
        ]
        let repo = self.repo
        let cart = self.cart
        return Task {
            switch await repo.placeOrder(fields: fields, screenshot: screenshot) {
            case .success:
                let notRestored = await cart.afterOrder(left)
                state.submitting = false
                state.done = true
                state.notRestored = notRestored
            case .failure(let e):
                state.submitting = false
                state.error = e.message
            }
        }
    }
}
