import SwiftUI

// MARK: - list

struct BookstoreScreen: View {
    var body: some View {
        WithModel({ app in
            let repo = app.repo
            return PagedListModel<Book> { page, query, _ in await repo.books(page: page, search: query) }
        }) { model in
            WithModel({ CartModel(cart: $0.cart, auth: $0.auth) }) { _ in BookstoreContent(model: model) }
        }
    }
}

private struct BookstoreContent: View {
    let model: PagedListModel<Book>
    @Environment(Navigator.self) private var nav

    var body: some View {
        DetailScaffold("Bookstore", actions: { CartAction { nav.signedIn(.cart) } }) {
            BookGrid(model: model) { nav.push(.book(id: $0)) }
        }
    }
}

/// Two columns of covers (as many 150pt columns as fit), search on top, more as the end comes near.
private struct BookGrid: View {
    let model: PagedListModel<Book>
    let onOpenBook: (String) -> Void

    var body: some View {
        let state = model.state
        let books = distinctByKey(state.items, \.id).map(\.1)
        ScrollView {
            VStack(spacing: 20) {
                SearchField(initial: state.query, placeholder: "Search books") { model.search($0) }
                if let error = state.error, state.items.isEmpty {
                    ErrorState(message: error) { model.refresh() }
                } else if !state.loading, state.items.isEmpty {
                    EmptyState(title: "No books found")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16, alignment: .top)], spacing: 20) {
                    ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                        BookGridTile(book: book) { onOpenBook(book.id) }
                            .onAppear {
                                // Near the end: ask for the next page (not after a failed page; that waits for Retry).
                                if state.error == nil, index >= books.count - 4 { model.loadMore() }
                            }
                    }
                }
                if let error = state.error, !state.items.isEmpty { LoadMoreError(message: error) { model.retry() } }
                if state.loading, !state.refreshing { LoadingBox(height: 80) }
            }
            .padding(Spacing.screen)
        }
        .refreshable { await model.refreshAndWait() }
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - detail

struct BookScreen: View {
    let id: String

    var body: some View {
        WithModel({ app in
            let repo = app.repo
            let id = self.id
            return Loader<Book> { await repo.book(id) }
        }) { loader in
            WithModel({ CartModel(cart: $0.cart, auth: $0.auth) }) { cartModel in
                BookContent(id: id, loader: loader, cartModel: cartModel)
            }
        }
    }
}

private struct BookContent: View {
    let id: String
    let loader: Loader<Book>
    let cartModel: CartModel
    @Environment(Navigator.self) private var nav
    @Environment(AppContainer.self) private var app

    var body: some View {
        DetailScaffold("", actions: { CartAction { nav.signedIn(.cart) } }) {
            LoadContent(state: loader.state, onRetry: { loader.load() }) { book in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear
                            .aspectRatio(0.72, contentMode: .fit)
                            .overlay { RemoteImage(path: book.imagePath, contentDescription: book.title) }
                            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                            .frame(width: 220)
                            .frame(maxWidth: .infinity)
                        Spacer().frame(height: 20)
                        Text(book.title).textStyle(Typo.headlineSmall).foregroundStyle(Scheme.onSurface)
                        Text(book.author).textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurfaceVariant)
                        Spacer().frame(height: 10)
                        StatusChip(bookStatusLabel(book.status), tone: bookStatusTone(book.status))
                        if let message = cartModel.message {
                            Spacer().frame(height: 10)
                            Banner(message, tone: .danger)
                        }
                        Spacer().frame(height: 16)
                        Text(book.description).textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurface)
                    }
                    .padding(Spacing.screen)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let book = loader.state.value { buyBar(book) }
        }
    }

    private func buyBar(_ book: Book) -> some View {
        let inCart = cartModel.cart.quantityOf(id)
        return HStack(alignment: .center, spacing: 0) {
            PriceLine(pricePaise: book.priceInrPaise, mrpPaise: book.mrpInrPaise)
                .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if book.status != "AVAILABLE" {
                    PrimaryButton(bookStatusLabel(book.status), enabled: false) {}
                } else if app.session == nil {
                    PrimaryButton("Sign in to buy") { nav.push(.signIn) }
                } else if inCart > 0 {
                    CartStepper(title: book.title, quantity: inCart) { cartModel.change(id, by: $0) }
                } else {
                    PrimaryButton("Add to cart") { cartModel.add(id) }
                }
            }
            .frame(width: 180)
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.vertical, 12)
        .background(Scheme.surfaceContainerLowest.ignoresSafeArea(edges: .bottom))
        .shadow(color: Brand.cardShadow, radius: 8, x: 0, y: -2)
    }
}

/// The status chip's colour on the book page.
func bookStatusTone(_ status: String) -> Tone {
    switch status {
    case "AVAILABLE": .success
    case "COMING_SOON": .info
    default: .danger
    }
}

// MARK: - checkout

struct CheckoutScreen: View {
    var body: some View {
        WithModel({ CheckoutModel(repo: $0.repo, cart: $0.cart) }) { model in CheckoutContent(model: model) }
    }
}

private struct CheckoutContent: View {
    let model: CheckoutModel
    @Environment(Navigator.self) private var nav
    @State private var method = "upi"
    @State private var reference = ""
    @State private var address = ""
    @State private var pin = ""
    @State private var phone = ""
    @State private var proof = ProofImagePicker()

    var body: some View {
        let state = model.state
        DetailScaffold("Checkout") {
            if state.done {
                MessageState(
                    icon: .checkCircle,
                    title: "Order submitted",
                    message: "The academy will verify your payment and ship the books. Track it under Account → Orders." +
                        notRestoredNote(state.notRestored),
                    action: "Done",
                    // Orders replaces the cart and the finished checkout: Back must not return to "Order submitted".
                    onAction: { nav.replace(upTo: .cart, with: .orders) }
                )
            } else {
                LoadContent(state: state.quote, onRetry: { model.load() }) { quote in form(quote, state) }
            }
        }
    }

    private func form(_ quote: CheckoutQuote, _ state: CheckoutState) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AppCard {
                    Overline(text: "Order summary")
                    Spacer().frame(height: 8)
                    ForEach(Array(quote.lines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(line.quantity) × \(line.title)").textStyle(Typo.bodyMedium).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(rupees(line.lineTotalInrPaise)).textStyle(Typo.bodyMedium)
                        }
                        .foregroundStyle(Scheme.onSurface)
                        .padding(.vertical, 3)
                    }
                    Rectangle().fill(Brand.outlineSoft).frame(height: 1).padding(.vertical, 8)
                    HStack(alignment: .firstTextBaseline) {
                        Text("Shipping").textStyle(Typo.bodyMedium).frame(maxWidth: .infinity, alignment: .leading)
                        Text(rupees(quote.shippingChargeInrPaise)).textStyle(Typo.bodyLarge)
                    }
                    .foregroundStyle(Scheme.onSurface)
                    HStack(alignment: .firstTextBaseline) {
                        Text("Total").textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(rupees(quote.totalAmountInrPaise)).textStyle(Typo.titleLarge).foregroundStyle(Scheme.primary)
                    }
                    .padding(.top, 6)
                }
                Text("Delivery").textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface)
                deliveryFields
                Text("Payment").textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface)
                PaymentDetailsError(message: state.settingsError) { model.reloadSettings() }
                PayWithUpiButton(settings: state.settings, amountPaise: quote.totalAmountInrPaise, note: "Book order")
                PaymentDetailsCard(settings: state.settings)
                PaymentConfirmFields(settings: state.settings, method: $method, reference: $reference, proof: proof)
                if let error = state.error { Banner(error, tone: .danger) }
                PrimaryButton(
                    "Submit Order for Approval",
                    enabled: address.trimmed.count >= 10 && pin.count >= 5 && phone.count >= 10 && reference.count >= 6,
                    loading: state.submitting
                ) {
                    model.place(method: method, reference: reference, address: address, pin: pin, phone: phone, screenshot: proof.image?.upload)
                }
                Spacer().frame(height: 16)
            }
            .padding(Spacing.screen)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// The website's delivery fields (Delivery Address, Pin Code, Phone Number); digits only where it takes digits.
    @ViewBuilder private var deliveryFields: some View {
        OutlinedField(
            label: "Delivery Address",
            text: Binding(get: { address }, set: { address = $0.jsPrefix(500) }),
            placeholder: "Enter your full address (Street, City, State)...",
            contentType: .fullStreetAddress,
            lines: 3...3
        )
        WeightRow(weights: [1, 1.3], spacing: 10) {
            OutlinedField(
                label: "Pin Code",
                text: Binding(get: { pin }, set: { pin = String($0.filter(\.isASCIIDigit).prefix(10)) }),
                placeholder: "e.g. 193402",
                keyboard: .numberPad,
                contentType: .postalCode
            )
            OutlinedField(
                label: "Phone Number",
                text: Binding(get: { phone }, set: { phone = String($0.filter(\.isASCIIDigit).prefix(15)) }),
                placeholder: "e.g. 9876543210",
                keyboard: .phonePad,
                contentType: .telephoneNumber
            )
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}

// MARK: - orders

struct OrdersScreen: View {
    var body: some View {
        WithModel({ app in
            let repo = app.repo
            return Loader<[BookOrder]> { await repo.orders() }
        }) { loader in OrdersContent(loader: loader) }
    }
}

private struct OrdersContent: View {
    let loader: Loader<[BookOrder]>
    @Environment(Navigator.self) private var nav

    var body: some View {
        DetailScaffold("Book orders") {
            LoadContent(state: loader.state, onRetry: { loader.load() }) { orders in
                if orders.isEmpty {
                    EmptyState(title: "No orders yet", message: "Books you order appear here with their delivery status.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(orders) { order in OrderCard(order: order) { nav.push(.order(id: order.id)) } }
                        }
                        .padding(Spacing.screen)
                    }
                }
            }
        }
    }
}

private struct OrderCard: View {
    let order: BookOrder
    let onClick: () -> Void

    var body: some View {
        let (label, tone) = statusLabel(order.status, kind: .order)
        AppCard(onClick: onClick) {
            HStack(alignment: .center, spacing: 0) {
                Icon.bagFilled.image.font(.system(size: 20, weight: .medium)).foregroundStyle(Brand.gold).accessibilityHidden(true)
                Spacer().frame(width: 10)
                Text(orderNumber(order.id)).textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                StatusChip(label, tone: tone)
            }
            Spacer().frame(height: 6)
            Text(order.items.map { "\($0.quantity) × \($0.book?.title ?? "Book")" }.joined(separator: ", "))
                .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                .lineLimit(2).multilineTextAlignment(.leading)
            Spacer().frame(height: 6)
            HStack(alignment: .firstTextBaseline) {
                Text(formatDate(order.createdAt)).textStyle(Typo.labelMedium).foregroundStyle(Scheme.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(rupees(order.totalAmountInrPaise)).textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface)
            }
        }
    }
}

struct OrderScreen: View {
    let id: String

    var body: some View {
        WithModel({ app in
            let repo = app.repo
            let id = self.id
            return Loader<BookOrder> { await repo.order(id) }
        }) { loader in OrderContent(id: id, loader: loader) }
    }
}

private struct OrderContent: View {
    let id: String
    let loader: Loader<BookOrder>

    var body: some View {
        DetailScaffold(orderNumber(id)) {
            LoadContent(state: loader.state, onRetry: { loader.load() }) { order in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        let (label, tone) = statusLabel(order.status, kind: .order)
                        HStack(spacing: 10) {
                            StatusChip(label, tone: tone)
                            Text("Placed \(formatDate(order.createdAt))").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurface)
                        }
                        if order.status == "SHIPPED" {
                            Banner(
                                "Shipped with \(order.courierServiceName ?? "the courier")\(order.trackingId.map { " · tracking \($0)" } ?? "")",
                                tone: .info, icon: .localShipping
                            )
                        }
                        AppCard {
                            ForEach(order.items) { item in
                                HStack(alignment: .center, spacing: 0) {
                                    RemoteImage(path: item.book?.imagePath, contentDescription: item.book?.title)
                                        .frame(width: 44, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: Radius.input))
                                    Spacer().frame(width: 12)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(item.book?.title ?? "Book").textStyle(Typo.titleSmall)
                                        Text("\(item.quantity) × \(rupees(item.priceAtPurchaseInrPaise))").textStyle(Typo.bodySmall)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(rupees(item.quantity * item.priceAtPurchaseInrPaise)).textStyle(Typo.titleSmall)
                                }
                                .foregroundStyle(Scheme.onSurface)
                                .padding(.vertical, 6)
                            }
                            Rectangle().fill(Brand.outlineSoft).frame(height: 1).padding(.vertical, 8)
                            HStack(alignment: .firstTextBaseline) {
                                Text("Shipping").textStyle(Typo.bodyLarge).frame(maxWidth: .infinity, alignment: .leading)
                                Text(rupees(order.shippingChargeInrPaise)).textStyle(Typo.bodyLarge)
                            }
                            .foregroundStyle(Scheme.onSurface)
                            HStack(alignment: .firstTextBaseline) {
                                Text("Total").textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(rupees(order.totalAmountInrPaise)).textStyle(Typo.titleMedium).foregroundStyle(Scheme.primary)
                            }
                        }
                        AppCard {
                            Overline(text: "Delivery")
                            Spacer().frame(height: 6)
                            Text(order.deliveryAddress ?? "").textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface)
                            Text([order.deliveryPinCode, order.deliveryPhoneNumber].compactMap { $0 }.joined(separator: " · "))
                                .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                        }
                    }
                    .padding(Spacing.screen)
                }
            }
        }
    }
}
