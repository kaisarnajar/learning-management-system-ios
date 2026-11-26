import Observation
import SwiftUI

/*
 * /admin/payments and /admin/completed-payments (Android's ui/manage/money/PaymentsScreens.kt): pending fee payments
 * to approve or decline, and every completed payment by tab, with receipts and Void.
 */

// MARK: - /admin/payments

/// The pending payments list, its tab counts, and the payment waiting for the admin to confirm a decision.
@MainActor
@Observable
final class MoneyPendingModel {
    let list: PagedListModel<MoneyRow>
    let counts: MoneyListExtras<[String: Int]>
    let runner: ActionRunner
    /// The payment whose "Confirm" dialog is open.
    var approving: MoneyRow?
    /// The payment whose "Decline" dialog is open.
    var declining: MoneyRow?

    init(app: AppContainer) {
        let counts = MoneyListExtras<[String: Int]>()
        self.counts = counts
        runner = ActionRunner(app: app)
        list = PagedListModel(app: app) { app, page, q, filter in
            let r = try await app.service(MoneyAPI.self).pending(type: filter ?? "enrollment_pending", page: page, q: q.trimmed.isEmpty ? nil : q)
            counts.value = r.counts
            return Paged(data: r.data, totalCount: r.totalCount, page: r.page, pageSize: r.pageSize)
        }
    }

    /// A card's Confirm or Decline: asks first.
    func decide(_ row: MoneyRow, approve: Bool) {
        if approve { approving = row } else { declining = row }
    }

    static func approveMessage(_ row: MoneyRow) -> String {
        "Approve this payment of \(money(row.amountInrPaise)) from \(row.user?.display ?? "this student") and notify the student?"
    }

    /// The Confirm dialog's "Confirm".
    func approve(_ row: MoneyRow) {
        let list = self.list
        runner.run({ try await $0.service(MoneyAPI.self).approve(row.id) }, success: "Payment approved and recorded. The student will be notified.") { _ in
            list.refresh()
        }
    }

    /// The Decline dialog's "Decline".
    func decline(_ row: MoneyRow) {
        let list = self.list
        runner.run({ try await $0.service(MoneyAPI.self).decline(row.id) }, success: "Payment declined. The student has been notified and can resubmit.") { _ in
            list.refresh()
        }
    }
}

/// Pending fee payments: check the screenshot and reference, then approve or decline.
struct PendingPaymentsScreen: View {
    var body: some View {
        WithModel({ MoneyPendingModel(app: $0) }) { MoneyPendingContent(model: $0) }
    }
}

private struct MoneyPendingContent: View {
    @Bindable var model: MoneyPendingModel

    var body: some View {
        let state = model.list.state
        let counts = model.counts.value ?? [:]
        ManageScaffold("Pending payments") {
            PagedListBody(
                model.list, searchHint: "Name, e-mail, course or reference",
                emptyTitle: state.query.trimmed.isEmpty ? "No payments found for this category." : "No payments match your search.",
                key: \.id,
                header: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Verify enrollment and fee payments submitted by students awaiting approval.")
                            .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                        Spacer().frame(height: 8)
                        FilterChips(
                            options: [
                                FilterOption(nil, "Enrollment Fee Pending" + moneyCount(counts["enrollment_pending"])),
                                FilterOption("monthly_pending", "Course Fee Pending" + moneyCount(counts["monthly_pending"])),
                            ],
                            selected: state.filter
                        ) { model.list.filter($0) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            ) { row in
                MoneySubmissionCard(row: row, runner: model.runner, onChanged: { model.list.refresh() }) { approve in
                    model.decide(row, approve: approve)
                }
            }
        }
        .reloadOnReturn { model.list.refresh() }
        .confirmDialog(item: $model.approving, title: "Confirm payment", message: MoneyPendingModel.approveMessage, confirm: "Confirm") {
            model.approve($0)
        }
        .confirmDialog(
            item: $model.declining, title: "Decline payment", message: { _ in "Decline this payment and ask the student to resubmit? They will be notified." },
            confirm: "Decline", destructive: true
        ) { model.decline($0) }
    }
}

/// " (3)" after a tab's label when it has waiting payments.
private func moneyCount(_ count: Int?) -> String {
    guard let count, count > 0 else { return "" }
    return " (\(count))"
}

/// The card's title block: the student and, when they have a name, their e-mail; the amount at the end.
private struct MoneyCardHeader: View {
    let title: String
    let lines: [String]
    let amount: String
    var amountColor: Color = Scheme.onSurface

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurface)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(amount).textStyle(Typo.titleMedium).foregroundStyle(amountColor)
        }
    }
}

/// A fee submission as PaymentApprovalsTable shows it. Pending: approve / decline ([onDecide]). Approved: the
/// receipt and Void.
struct MoneySubmissionCard: View {
    let row: MoneyRow
    let runner: ActionRunner
    let onChanged: () -> Void
    let onDecide: (_ approve: Bool) -> Void
    @State private var voiding = false

    var body: some View {
        let approved = row.status?.lowercased() == "approved"
        AppCard(padding: 14) {
            MoneyCardHeader(title: row.user?.display ?? "—", lines: row.user?.name != nil ? [row.user?.email ?? ""] : [], amount: money(row.amountInrPaise))
            Spacer().frame(height: 8)
            VStack(alignment: .leading, spacing: 2) {
                MoneyInfoLine("Course", row.courseTitle)
                MoneyInfoLine("Description", row.label)
                MoneyInfoLine("Method", row.paymentMethod.map(moneyCapitalized) ?? "—")
                MoneyInfoLine("Reference", row.reference ?? "—")
                MoneyInfoLine("Submitted", formatDate(row.submittedAt))
            }
            if !(row.screenshotPath?.trimmed.isEmpty ?? true) {
                Spacer().frame(height: 8)
                MoneyScreenshotThumb(path: row.screenshotPath, isPdf: row.screenshotIsPdf)
            }
            Spacer().frame(height: 10)
            MoneyFlowRow(spacing: 8, lineSpacing: 4) {
                if !approved {
                    MoneyCtaButton("Confirm", icon: .checkCircle, enabled: !runner.busy) { onDecide(true) }
                    MoneyOutlinedButton("Decline", color: Scheme.error, enabled: !runner.busy) { onDecide(false) }
                } else {
                    MoneyReceiptButton(recordId: row.paymentRecordId, generatedAt: row.receiptGeneratedAt, runner: runner, onGenerated: onChanged)
                    BarTextButton("Void", enabled: !runner.busy, color: Scheme.error) { voiding = true }
                }
            }
        }
        .textInputDialog(
            isPresented: $voiding, title: "Void this payment?", label: "Reason for voiding", confirmLabel: "Void", required: true,
            message: "The payment record is kept for the audit log but no longer counts as income.", destructive: true
        ) { reason in
            runner.run({ try await $0.service(MoneyAPI.self).voidPayment(row.id, moneyReasonForm(reason)) }, success: "Payment voided.") { _ in onChanged() }
        }
    }
}

// MARK: - /admin/completed-payments

private let moneyCompletedTabs = [
    FilterOption(nil, "Enrollment Fee Approved"),
    FilterOption("monthly_approved", "Course Fee Approved"),
    FilterOption("enrollment_waiver", "100% Waiver (Enrollment)"),
    FilterOption("monthly_waiver", "100% Waiver (Course)"),
    FilterOption("book_approved", "Book Order Payments"),
    FilterOption("book_refunded", "Book Order Refunds"),
    FilterOption("manual_transactions", "Manual Transactions"),
    FilterOption("manual_expenses", "Manual Expenses"),
]

@MainActor
final class MoneyCompletedModel {
    let list: PagedListModel<MoneyRow>
    let runner: ActionRunner

    init(app: AppContainer) {
        runner = ActionRunner(app: app)
        list = PagedListModel(app: app) { app, page, q, filter in
            let r = try await app.service(MoneyAPI.self).completed(type: filter ?? "enrollment_approved", page: page, q: q.trimmed.isEmpty ? nil : q)
            return Paged(data: r.data, totalCount: r.totalCount, page: r.page, pageSize: r.pageSize)
        }
    }
}

/// Every completed payment by tab: approved fees and waivers, book orders, manual transactions and expenses.
struct CompletedPaymentsScreen: View {
    var body: some View {
        WithModel({ MoneyCompletedModel(app: $0) }) { MoneyCompletedContent(model: $0) }
    }
}

private struct MoneyCompletedContent: View {
    let model: MoneyCompletedModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let state = model.list.state
        let refresh = { model.list.refresh() }
        ManageScaffold("Completed payments", actions: {
            IconButton(.receipt, label: "Payment receipts") { nav.push(.manage(.receipts)) }
        }) {
            PagedListBody(
                model.list, searchHint: "Name, e-mail, course or reference",
                emptyTitle: state.query.trimmed.isEmpty ? "No payments found for this category." : "Nothing matches your search.",
                key: { $0.kind + $0.id },
                header: { FilterChips(options: moneyCompletedTabs, selected: state.filter) { model.list.filter($0) } }
            ) { row in
                switch row.kind {
                case "submission": MoneySubmissionCard(row: row, runner: model.runner, onChanged: refresh) { _ in }
                case "book_order": MoneyBookOrderPaymentCard(row: row, runner: model.runner, onChanged: refresh)
                case "income": MoneyIncomeCard(row: row, runner: model.runner, onChanged: refresh, canVoid: true)
                case "expense": MoneyExpenseCard(row: row, runner: model.runner, onChanged: refresh)
                default: EmptyView()
                }
            }
        }
        .reloadOnReturn { model.list.refresh() }
    }
}

/// A book order's payment (BookOrdersTable in payment-only mode).
struct MoneyBookOrderPaymentCard: View {
    let row: MoneyRow
    let runner: ActionRunner
    let onChanged: () -> Void
    @State private var voiding = false

    var body: some View {
        let email = row.user?.name != nil ? row.user?.email : nil
        let status = moneyStatus(row.status, label: row.statusLabel)
        AppCard(padding: 14) {
            MoneyCardHeader(
                title: row.user?.display ?? "—", lines: [[email, formatDate(row.createdAt)].compactMap { $0 }.joined(separator: " · ")],
                amount: money(row.amountInrPaise)
            )
            Spacer().frame(height: 6)
            StatusChip(status.0, tone: status.1)
            Spacer().frame(height: 6)
            ForEach(row.items) { item in
                Text("\(item.title) × \(item.quantity) — \(money(item.lineTotalPaise))").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurface)
            }
            Spacer().frame(height: 6)
            VStack(alignment: .leading, spacing: 2) {
                MoneyInfoLine("Address", row.deliveryAddress ?? "No address provided")
                MoneyInfoLine("PIN", row.deliveryPinCode)
                MoneyInfoLine("Phone", row.deliveryPhoneNumber)
                MoneyInfoLine("Method", row.paymentMethod.map(moneyCapitalized) ?? "—")
                MoneyInfoLine("Reference", row.reference)
                MoneyInfoLine("Courier", row.courierServiceName)
                MoneyInfoLine("Tracking ID", row.trackingId)
            }
            if !(row.screenshotPath?.trimmed.isEmpty ?? true) {
                Spacer().frame(height: 8)
                MoneyScreenshotThumb(path: row.screenshotPath, isPdf: row.screenshotIsPdf)
            }
            Spacer().frame(height: 8)
            MoneyFlowRow(spacing: 8, lineSpacing: 0) {
                MoneyReceiptButton(recordId: row.paymentRecordId, generatedAt: row.receiptGeneratedAt, runner: runner, onGenerated: onChanged)
                if row.canVoid { BarTextButton("Void", enabled: !runner.busy, color: Scheme.error) { voiding = true } }
            }
        }
        .textInputDialog(
            isPresented: $voiding, title: "Void this order?", label: "Reason for voiding", confirmLabel: "Void", required: true,
            message: "It stays on record for auditing but disappears from order lists and finance.", destructive: true
        ) { reason in
            runner.run({ try await $0.service(BookstoreAdminAPI.self).orderAction(row.id, action: "void", moneyReasonForm(reason)) }, success: "Order voided.") { _ in
                onChanged()
            }
        }
    }
}

/// A payment record (income): finance lists and manually added transactions. Without a [runner] it has no buttons.
struct MoneyIncomeCard: View {
    let row: MoneyRow
    let runner: ActionRunner?
    var onChanged: () -> Void = {}
    let canVoid: Bool
    @State private var voiding = false

    var body: some View {
        AppCard(padding: 14) {
            MoneyCardHeader(
                title: row.user?.display ?? "—", lines: [[formatDate(row.paidAt), row.paymentTypeLabel].compactMap { $0 }.joined(separator: " · ")],
                amount: money(row.amountInrPaise), amountColor: Brand.success
            )
            Spacer().frame(height: 4)
            MoneyInfoLine("Course", row.courseTitle ?? "—")
            MoneyInfoLine("Description", row.description)
            if let runner {
                Spacer().frame(height: 8)
                MoneyFlowRow(spacing: 8, lineSpacing: 0) {
                    MoneyReceiptButton(recordId: row.paymentRecordId, generatedAt: row.receiptGeneratedAt, runner: runner, onGenerated: onChanged)
                    if canVoid { BarTextButton("Void", enabled: !runner.busy, color: Scheme.error) { voiding = true } }
                }
            }
        }
        .textInputDialog(
            isPresented: $voiding, title: "Void this payment record?", label: "Reason for voiding", confirmLabel: "Void", required: true,
            message: "It is kept for the audit log and left out of finance.", destructive: true
        ) { reason in
            runner?.run({ try await $0.service(MoneyAPI.self).voidRecord(row.id, moneyReasonForm(reason)) }, success: "Payment record voided.") { _ in
                onChanged()
            }
        }
    }
}

/// An expense, with Delete.
struct MoneyExpenseCard: View {
    let row: MoneyRow
    let runner: ActionRunner
    let onChanged: () -> Void
    @State private var deleting = false

    var body: some View {
        AppCard(padding: 14) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.categoryLabel ?? row.category ?? "").textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurface)
                    if let note = row.note, !note.trimmed.isEmpty {
                        Text(note).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurface)
                    }
                    Text(formatDate(row.paidAt)).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(money(row.amountInrPaise)).textStyle(Typo.titleMedium).foregroundStyle(Brand.danger)
            }
            Spacer().frame(height: 4)
            MoneyInfoLine("Teacher", row.teacher?.name)
            MoneyInfoLine("Description", row.description)
            HStack {
                Spacer()
                BarTextButton("Delete", enabled: !runner.busy, color: Scheme.error) { deleting = true }
            }
        }
        .confirmDialog(
            "Delete this expense?",
            message: "\(row.categoryLabel ?? row.category ?? "This expense") of \(money(row.amountInrPaise)) on \(formatDate(row.paidAt)) is removed from finance. This cannot be undone.",
            isPresented: $deleting, confirm: "Delete", destructive: true
        ) {
            runner.run({ try await $0.service(MoneyAPI.self).deleteExpense(row.id) }, success: "Expense deleted.") { _ in onChanged() }
        }
    }
}
