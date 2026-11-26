import SwiftUI

/// A book left out of checkout is shown faded, as on the website's cart page.
private let unselectedAlpha = 0.5

struct CartScreen: View {
    var body: some View {
        WithModel({ CartModel(cart: $0.cart, auth: $0.auth) }) { model in CartContent(model: model) }
    }
}

private struct CartContent: View {
    let model: CartModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let cart = model.cart
        let items = cart.items
        DetailScaffold("My Cart") {
            if items.isEmpty {
                EmptyState(title: "Your cart is empty", message: "Browse our bookstore to add books.", action: "Browse Bookstore") { nav.pop() }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        Text("Select the books you want to buy, then proceed to checkout.")
                            .textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
                        HStack(spacing: 8) {
                            TextButton("Select all") { cart.selectAll(true) }
                            TextButton("Deselect all") { cart.selectAll(false) }
                            Spacer(minLength: 0)
                            Text("\(itemCount(cart.count)) in cart").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurface)
                        }
                        if let message = model.message { Banner(message, tone: .danger) }
                        ForEach(items) { item in
                            CartRow(
                                item: item,
                                selected: !cart.unselected.contains(item.bookId),
                                onSelect: { cart.select(item.bookId, $0) },
                                onChange: { model.change(item.bookId, by: $0) }
                            )
                        }
                    }
                    .padding(Spacing.screen)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !items.isEmpty {
                CartSummary(selected: cart.selectedItems(), emailVerified: model.emailVerified) { nav.push(.checkout) }
            }
        }
        .onAppear { model.checkEmail() }
    }
}

private struct CartRow: View {
    let item: CartItem
    let selected: Bool
    let onSelect: (Bool) -> Void
    let onChange: (Int) -> Void

    var body: some View {
        AppCard(padding: 12) {
            HStack(alignment: .center, spacing: 0) {
                Button { onSelect(!selected) } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(selected ? Scheme.primary : Scheme.onSurfaceVariant, lineWidth: 2)
                            .background(selected ? Scheme.primary : .clear, in: RoundedRectangle(cornerRadius: 2))
                            .frame(width: 18, height: 18)
                        if selected { Icon.check.image.font(.system(size: 12, weight: .bold)).foregroundStyle(Scheme.onPrimary) }
                    }
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Select \(item.title)")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                RemoteImage(path: item.imagePath, contentDescription: item.title)
                    .frame(width: 48, height: 66)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.input))
                Spacer().frame(width: 12)
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title).textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface).lineLimit(2)
                    Text(item.author).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                    PriceLine(pricePaise: item.priceInrPaise, mrpPaise: item.mrpInrPaise)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                CartStepper(title: item.title, quantity: item.quantity, onChange: onChange)
                    .frame(width: 120)
            }
        }
        .opacity(selected ? 1 : unselectedAlpha)
    }
}

private struct CartSummary: View {
    let selected: [CartItem]
    let emailVerified: Bool?
    let onCheckout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(itemCount(selected.count)) selected").textStyle(Typo.bodyMedium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Total: \(rupees(selected.reduce(0) { $0 + $1.priceInrPaise * $1.quantity }))").textStyle(Typo.titleMedium)
            }
            .foregroundStyle(Scheme.onSurface)
            Spacer().frame(height: 10)
            switch cartCheckout(emailVerified: emailVerified, selectedCount: selected.count) {
            case .verifyEmail:
                Banner("Verify your email to checkout", tone: .warning)
            case .nothingSelected:
                PrimaryButton("Proceed to Checkout (0 items)", enabled: false) {}
            case .ready:
                PrimaryButton("Proceed to Checkout (\(selected.count) \(selected.count == 1 ? "item" : "items"))", action: onCheckout)
            }
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.vertical, 12)
        .background(Scheme.surfaceContainerLowest.ignoresSafeArea(edges: .bottom))
        .shadow(color: Brand.cardShadow, radius: 8, x: 0, y: -2)
    }
}
