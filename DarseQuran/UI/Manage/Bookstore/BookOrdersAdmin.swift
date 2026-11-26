import Observation
import SwiftUI

/*
 * Book orders: /admin/bookstore/orders (pending, approved and completed tabs) and /admin/bookstore/orders/[id].
 * The website acts on orders from the list rows; the app offers the same actions on each card and on the detail.
 * Ported from Android's ui/manage/bookstore/BookOrdersAdmin.kt.
 */

// The order endpoints don't report whether the e-mail went out, so the message doesn't claim it did.
private let bookOrderNotified = "The student will be notified."

/// A tab's name with its count when there are any ("Approved (2)").
func bookOrdersTabLabel(_ name: String, _ n: Int?) -> String { if let n, n > 0 { "\(name) (\(n))" } else { name } }

/// The payment method as the website words it.
func bookOrderPaymentMethodLabel(_ method: String?) -> String {
    guard let method, !method.isEmpty else { return "—" }
    switch method.lowercased() {
    case "upi": return "UPI"
    case "bank", "bank_transfer": return "Bank transfer"
    case "cash": return "Cash"
    default:
        let spaced = method.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
}

/// Whether a payment proof is a PDF (which an image view would show as broken). The website tells them apart by the
/// file name, so this does too.
func isPdfProof(_ path: String) -> Bool {
    (path.components(separatedBy: "?").first ?? path).lowercased().hasSuffix(".pdf")
}

// MARK: - list

/// The list and its tab counts. The counts (every tab's total for the current search) come with each page of the list,
/// so there is no second request for them (Android's BookOrderBadges).
@MainActor
@Observable
final class BookOrdersListModel {
    var counts: BookOrderCounts?
    @ObservationIgnored private(set) var list: PagedListModel<BookOrderRow>!
    let runner: ActionRunner

    init(app: AppContainer) {
        runner = ActionRunner(app: app)
        list = PagedListModel(app: app) { [weak self] app, page, q, status in
            let r = try await app.service(BookstoreAdminAPI.self).orders(page: page, q: q.trimmed.isEmpty ? nil : q, status: status)
            self?.counts = r.counts
            return r.paged()
        }
    }
}

struct BookOrdersListScreen: View {
    var body: some View {
        WithModel({ BookOrdersListModel(app: $0) }) { model in BookOrdersListContent(model: model) }
    }
}

private struct BookOrdersListContent: View {
    let model: BookOrdersListModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let state = model.list.state
        let c = model.counts
        let searching = !state.query.trimmed.isEmpty
        let empty = switch state.filter {
        case "approved": searching ? "No approved orders match your search." : "No approved orders awaiting fulfillment."
        case "completed": searching ? "No completed orders match your search." : "No completed orders found."
        default: searching ? "No pending orders match your search." : "No book orders awaiting verification."
        }
        ManageListScreen(
            "Book orders", model: model.list, key: \.id, emptyTitle: empty, searchHint: "Name, e-mail or transaction ID",
            filters: [
                FilterOption(nil, bookOrdersTabLabel("Pending approvals", c?.pending)),
                FilterOption("approved", bookOrdersTabLabel("Approved", c?.approved)),
                FilterOption("completed", bookOrdersTabLabel("Completed", c?.completed)),
            ],
            // Android navigates with launchSingleTop, which only matters when the books list is on top (it never is here).
            actions: { IconButton(.courses, label: "Manage books") { nav.push(.manage(.booksAdmin)) } }
        ) { order in
            BookOrderCard(order: order, runner: model.runner, onOpen: { nav.push(.manage(.bookOrderAdmin(id: order.id))) }) {
                model.list.refresh()
            }
        }
        .reloadOnReturn { model.list.refresh() }
    }
}

private struct BookOrderCard: View {
    let order: BookOrderRow
    let runner: ActionRunner
    let onOpen: () -> Void
    let onChanged: () -> Void

    var body: some View {
        // Not a Button card: its approve / decline / ship buttons would sit inside the card's own button, where VoiceOver
        // can't reach them. A tap anywhere else, or VoiceOver's "Open order" action, opens the order.
        AppCard(padding: 14) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(order.customerName ?? "—").textStyle(Typo.titleSmall).fontWeight(.semibold).foregroundStyle(Scheme.onSurface)
                    Text(order.customerEmail).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                    Text("Order \(order.shortId) · \(formatDate(order.createdAt))").textStyle(Typo.labelSmall).foregroundStyle(Scheme.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(rupees(order.totalAmountInrPaise)).textStyle(Typo.titleSmall).fontWeight(.semibold).foregroundStyle(Scheme.onSurface)
                    StatusChip(order.statusLabel.trimmed.isEmpty ? order.status : order.statusLabel, tone: orderStatusTone(order.status))
                }
            }
            Spacer().frame(height: 8)
            ForEach(order.items) { item in
                Text("\(item.title) × \(item.quantity) — \(rupees(item.lineTotalInrPaise))").textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface)
                    .multilineTextAlignment(.leading)
            }
            Spacer().frame(height: 8)
            Text(addressText).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant).multilineTextAlignment(.leading)
            Spacer().frame(height: 6)
            Text([bookOrderPaymentMethodLabel(order.paymentMethod), order.upiTransactionId.map { "Ref. \($0)" }].compactMap { $0 }.joined(separator: " · "))
                .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurface)
            if order.status == "SHIPPED", let courier = order.courierServiceName {
                Text("Courier: \(courier) · Tracking ID: \(order.trackingId ?? "—")").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
            }
            Spacer().frame(height: 8)
            BookOrderActions(id: order.id, status: order.status, runner: runner, proofPath: order.paymentScreenshotPath, onChanged: onChanged)
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open order", onOpen)
    }

    private var addressText: String {
        guard let addr = order.deliveryAddress else { return "No address provided" }
        return [addr, order.deliveryPinCode.map { "PIN: \($0)" }, order.deliveryPhoneNumber.map { "Phone: \($0)" }].compactMap { $0 }.joined(separator: "\n")
    }
}

// MARK: - actions

/// A status change waiting for the admin's confirmation.
private enum BookOrderConfirm: Hashable { case approve, decline, refund }

/// The status changes the website offers for an order in [status].
struct BookOrderActions: View {
    let id: String
    let status: String
    let runner: ActionRunner
    /// The payment screenshot, shown first in the row on the list's cards.
    var proofPath: String? = nil
    let onChanged: () -> Void
    @State private var confirm: BookOrderConfirm?
    @State private var shipping = false
    @State private var voiding = false

    var body: some View {
        // One flow row (not a Group: a Group would give every button its own copy of the dialogs below). Each button is
        // its own child so they wrap one at a time, like Android's FlowRow.
        BookstoreFlowRow(spacing: 8, lineSpacing: 4) {
            if let proofPath { BookstoreProofThumb(path: proofPath) }
            switch status {
            case "PENDING_VERIFICATION":
                BookstoreCtaButton("Approve", enabled: !runner.busy) { confirm = .approve }
                BookstoreOutlinedDanger("Decline", enabled: !runner.busy) { confirm = .decline }
            case "APPROVED":
                BookstoreCtaButton("Mark as shipped", enabled: !runner.busy) { shipping = true }
                BookstoreOutlinedDanger("Refund", enabled: !runner.busy) { confirm = .refund }
            case "SHIPPED":
                BookstoreOutlinedDanger("Refund", enabled: !runner.busy) { confirm = .refund }
            case "DECLINED", "REFUNDED":
                BookstoreOutlinedDanger("Void", enabled: !runner.busy) { voiding = true }
            default:
                EmptyView()
            }
        }
        .alert(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), presenting: confirm) { c in
            Button("Cancel", role: .cancel) {}
            switch c {
            case .approve: Button("Approve") { act("approve", "Order approved. \(bookOrderNotified)") }
            case .decline: Button("Decline", role: .destructive) { act("decline", "Order declined. \(bookOrderNotified)") }
            case .refund: Button("Refund", role: .destructive) { act("refund", "Order refunded. \(bookOrderNotified)") }
            }
        } message: { c in
            switch c {
            case .approve: Text("Approve this book order and notify the student?")
            case .decline: Text("Are you sure you want to decline this order?")
            case .refund:
                Text(
                    status == "SHIPPED"
                        ? "Refund this shipped order? The recorded payment will be voided and the student notified."
                        : "Are you sure you want to refund this order? The student will be notified."
                )
            }
        }
        .textInputDialog(
            isPresented: $voiding, title: "Void order", label: "Reason for voiding", confirmLabel: "Void", required: true,
            message: "Void this order? It stays on record for auditing but disappears from order lists and finance.", destructive: true
        ) { reason in
            act("void", "Order voided.") { $0.text("reason", reason) }
        }
        .materialDialog(isPresented: $shipping) {
            BookOrderShipDialog(onDismiss: { shipping = false }) { courier, tracking in
                act("ship", "Order marked as shipped. \(bookOrderNotified)") { f in
                    f.text("courierServiceName", courier)
                    f.text("trackingId", tracking)
                }
            }
        }
    }

    private var confirmTitle: String {
        switch confirm {
        case .approve: "Approve order"
        case .decline: "Decline order"
        case .refund: "Refund order"
        case nil: ""
        }
    }

    private func act(_ action: String, _ success: String, _ fields: @escaping (inout FormFields) -> Void = { _ in }) {
        let id = id
        let form = formOf(fields)
        runner.run({ try await $0.service(BookstoreAdminAPI.self).orderAction(id, action: action, form) }, success: success) { _ in onChanged() }
    }
}

/// "Mark as shipped": the courier and tracking ID the student is told.
private struct BookOrderShipDialog: View {
    let onDismiss: () -> Void
    let onConfirm: (String, String) -> Void
    @State private var courier = ""
    @State private var tracking = ""

    var body: some View {
        DialogTitle("Mark as shipped")
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter shipment details to notify the student.").textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
            OutlinedField(
                label: "Courier service name", text: Binding(get: { courier }, set: { courier = $0.jsPrefix(100) }),
                placeholder: "e.g. DTDC, India Post", capitalization: .words, autocorrect: false
            )
            OutlinedField(
                label: "Tracking ID", text: Binding(get: { tracking }, set: { tracking = $0.jsPrefix(100) }),
                capitalization: .characters, autocorrect: false
            )
        }
        .environment(\.fieldSurface, Scheme.surfaceContainerHigh)
        DialogButtons(
            dismissLabel: "Cancel", confirmLabel: "Confirm shipment", confirmEnabled: !courier.trimmed.isEmpty && !tracking.trimmed.isEmpty,
            onDismiss: onDismiss
        ) {
            onDismiss()
            onConfirm(courier.trimmed, tracking.trimmed)
        }
    }
}

/// Material's filled Button in the CTA colours (gold).
private struct BookstoreCtaButton: View {
    let label: String
    var enabled: Bool = true
    let action: () -> Void

    init(_ label: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.label = label
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label).textStyle(Typo.labelLarge).lineLimit(1).padding(.horizontal, 24).frame(minHeight: 40)
        }
        .buttonStyle(FilledStyle(background: Brand.cta, foreground: Brand.onCta, radius: 20))
        .disabled(!enabled)
    }
}

/// Material's OutlinedButton with an error-coloured label.
private struct BookstoreOutlinedDanger: View {
    let label: String
    var enabled: Bool = true
    let action: () -> Void

    init(_ label: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.label = label
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label).textStyle(Typo.labelLarge).lineLimit(1)
                .foregroundStyle(enabled ? Scheme.error : Scheme.onSurface.opacity(0.38))
                .padding(.horizontal, 24)
                .frame(minHeight: 40)
                .overlay(Capsule().strokeBorder(enabled ? Scheme.outline : Scheme.onSurface.opacity(0.12), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(shape: Capsule()))
        .disabled(!enabled)
    }
}

// MARK: - payment proof

/// The order's payment proof: a 64pt thumbnail that opens full screen, or "Open proof (PDF)" for a PDF (Android's
/// ScreenshotThumb).
private struct BookstoreProofThumb: View {
    let path: String
    @Environment(AppContainer.self) private var app
    @State private var open = false

    var body: some View {
        if isPdfProof(path) {
            PillOutlinedButton("Open proof (PDF)", icon: .pdf) {
                let client = app.client, toaster = app.toaster, path = path
                Task {
                    if let message = await downloadAndOpen(client, path: path, fileName: "payment-proof.pdf") { toaster.show(message, long: true) }
                }
            }
        } else {
            HStack(alignment: .center, spacing: 10) {
                Button { open = true } label: {
                    RemoteImage(path: path, contentDescription: "Payment screenshot")
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                Text("Tap to view the screenshot").textStyle(Typo.labelSmall).foregroundStyle(Scheme.onSurfaceVariant)
            }
            .fullScreenCover(isPresented: $open) {
                ZStack(alignment: .topTrailing) {
                    Color.black.ignoresSafeArea()
                    RemoteImage(path: path, contentDescription: "Payment screenshot", contentMode: .fit)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    IconButton(.close, label: "Close", tint: .white) { open = false }
                }
            }
        }
    }
}

/// Lays its children out left to right, wrapping onto new lines (Compose's FlowRow).
struct BookstoreFlowRow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + lineSpacing; rowHeight = 0 }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? widest : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + lineSpacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - detail

@MainActor
@Observable
final class BookOrderDetailModel {
    let loader: Loader<BookOrderResponse>
    let runner: ActionRunner

    init(app: AppContainer, id: String) {
        loader = Loader(app: app) { try await $0.service(BookstoreAdminAPI.self).order(id) }
        runner = ActionRunner(app: app)
    }
}

struct BookOrderDetailScreen: View {
    let id: String

    var body: some View {
        WithModel({ BookOrderDetailModel(app: $0, id: id) }) { model in BookOrderDetailContent(model: model) }
    }
}

private struct BookOrderDetailContent: View {
    let model: BookOrderDetailModel

    var body: some View {
        ManageScaffold("Book order") {
            LoadedColumn(model.loader) { r in
                let o = r.order
                DetailCard {
                    Text("Order \(o.shortId)").textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface)
                    HStack(spacing: 8) {
                        StatusChip(o.statusLabel.trimmed.isEmpty ? o.status : o.statusLabel, tone: orderStatusTone(o.status))
                        if o.deleted { StatusChip("Deleted", tone: .danger) }
                    }
                    Text("Placed \(formatDateTime(o.createdAt))").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                    if !o.deleted {
                        BookOrderActions(id: o.id, status: o.status, runner: model.runner) { model.loader.reload() }
                    }
                }
                DetailCard("Customer & delivery") {
                    Field("Name", o.customer.name)
                    Field("Email", o.customer.email)
                    Field("Phone", o.deliveryPhoneNumber)
                    Field("Address", [o.deliveryAddress, o.deliveryPinCode].compactMap { $0 }.joined(separator: " — "))
                    Field("Notes", o.notes, showEmpty: false)
                }
                DetailCard("Payment & shipment") {
                    Field("Method", bookOrderPaymentMethodLabel(o.paymentMethod))
                    Field("UTR / reference", o.upiTransactionId)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Proof").textStyle(Typo.labelMedium).foregroundStyle(Scheme.onSurfaceVariant)
                        if let proof = o.paymentScreenshotPath {
                            BookstoreProofThumb(path: proof)
                        } else {
                            Text("No screenshot uploaded").textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
                        }
                    }
                    if let courier = o.courierServiceName {
                        Field("Courier", courier)
                        Field("Tracking ID", o.trackingId)
                    }
                }
                DetailCard("Items") {
                    ForEach(o.items) { item in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.title).textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurface)
                                Text("\(item.author) · \(rupees(item.priceAtPurchaseInrPaise)) × \(item.quantity)")
                                    .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(rupees(item.lineTotalInrPaise)).textStyle(Typo.bodyMedium).fontWeight(.semibold).foregroundStyle(Scheme.onSurface)
                        }
                    }
                    ManageDivider()
                    FieldRow("Subtotal", rupees(o.subtotalInrPaise))
                    FieldRow("Shipping", rupees(o.shippingChargeInrPaise))
                    FieldRow("Total", rupees(o.totalAmountInrPaise), strong: true)
                }
                DetailCard("Timeline") {
                    BookOrderTimelineEntry(title: "Order placed", actor: nil, reason: nil, at: o.createdAt)
                    ForEach(r.timeline) { e in
                        BookOrderTimelineEntry(title: e.label.trimmed.isEmpty ? e.action : e.label, actor: e.actorEmail, reason: e.reason, at: e.createdAt)
                    }
                    if r.timeline.isEmpty {
                        Text("No admin actions recorded for this order yet. Status changes made before the audit log was introduced are not listed.")
                            .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                    }
                }
            }
        }
        .reloadOnReturn { model.loader.reload() }
    }
}

private struct BookOrderTimelineEntry: View {
    let title: String
    let actor: String?
    let reason: String?
    let at: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title + (actor.map { " by \($0)" } ?? "")).textStyle(Typo.bodyMedium).fontWeight(.medium).foregroundStyle(Scheme.onSurface)
            if let reason, !reason.trimmed.isEmpty {
                Text("Reason: \(reason)").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
            }
            Text(formatDateTime(at)).textStyle(Typo.labelSmall).foregroundStyle(Scheme.onSurfaceVariant)
        }
        .padding(.leading, 4)
    }
}
