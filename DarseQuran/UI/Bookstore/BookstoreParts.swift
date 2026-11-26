import SwiftUI

/// Cart icon with a count badge, for bookstore top bars (Android's CartAction).
struct CartAction: View {
    let onClick: () -> Void
    @Environment(CartStore.self) private var cart

    var body: some View {
        let count = cart.count
        Button(action: onClick) {
            Icon.cart.image
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Scheme.onSurface)
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        // Material's Badge: error colour, a 16pt pill with the count.
                        Text("\(count)")
                            .textStyle(Typo.labelSmall)
                            .foregroundStyle(Scheme.onError)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Scheme.error, in: Capsule())
                            .fixedSize()
                            .offset(x: 10, y: -8)
                    }
                }
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(shape: Circle()))
        .accessibilityLabel(count > 0 ? "Cart, \(itemCount(count))" : "Cart")
    }
}

/// − quantity + on the primary container; taking the last copy out asks first (Android's CartStepper).
struct CartStepper: View {
    let title: String
    let quantity: Int
    let onChange: (Int) -> Void
    @State private var confirmRemove = false

    var body: some View {
        HStack(spacing: 0) {
            stepButton(.remove, label: "Fewer", enabled: true) {
                if quantity == 1 { confirmRemove = true } else { onChange(-1) }
            }
            Spacer(minLength: 0)
            Text("\(quantity)").textStyle(Typo.titleMedium).foregroundStyle(Scheme.onPrimaryContainer)
                .accessibilityLabel("Quantity \(quantity)")
            Spacer(minLength: 0)
            stepButton(.add, label: "More", enabled: quantity < CartStore.maxPerBook) { onChange(1) }
        }
        .background(Scheme.primaryContainer, in: RoundedRectangle(cornerRadius: Radius.input))
        .alert("Remove from cart?", isPresented: $confirmRemove) {
            Button("Keep", role: .cancel) {}
            Button("Remove") { onChange(-1) }
        } message: {
            Text("\"\(title)\" will be taken out of your cart.")
        }
    }

    private func stepButton(_ icon: Icon, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        IconButton(icon, label: label, tint: enabled ? Scheme.onPrimaryContainer : Scheme.onSurface.opacity(0.38), action: action)
            .disabled(!enabled)
    }
}

/// A book in the bookstore grid: cover, title, author, price (Android's BookTile).
struct BookGridTile: View {
    let book: Book
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .aspectRatio(0.72, contentMode: .fit)
                    .overlay { RemoteImage(path: book.imagePath, contentDescription: book.title) }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.input))
                Spacer().frame(height: 8)
                Text(book.title).textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurface)
                    .lineLimit(2).multilineTextAlignment(.leading)
                Text(book.author).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant).lineLimit(1)
                Spacer().frame(height: 2)
                PriceLine(pricePaise: book.priceInrPaise, mrpPaise: book.mrpInrPaise)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Lays its children out side by side with widths in proportion to [weights] (Compose's Modifier.weight).
struct WeightRow: Layout {
    let weights: [CGFloat]
    var spacing: CGFloat = 10

    private func widths(_ total: CGFloat, _ count: Int) -> [CGFloat] {
        let available = max(0, total - spacing * CGFloat(max(count - 1, 0)))
        let sum = weights.prefix(count).reduce(0, +)
        return (0..<count).map { available * ($0 < weights.count ? weights[$0] : 1) / max(sum, 1) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let w = widths(width, subviews.count)
        let height = zip(subviews, w).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(bounds.width, subviews.count)) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: nil))
            x += width + spacing
        }
    }
}
