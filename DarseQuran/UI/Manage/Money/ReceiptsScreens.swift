import Observation
import SwiftUI

/*
 * /admin/receipts (Android's ui/manage/money/ReceiptsScreens.kt): every generated receipt, and one payment's receipt
 * (open the PDF, e-mail it, regenerate or delete it).
 */

// MARK: - /admin/receipts

@MainActor
@Observable
final class MoneyReceiptsModel {
    let list: PagedListModel<ReceiptRow>
    let runner: ActionRunner
    /// The receipt whose Delete dialog is open.
    var deleting: ReceiptRow?

    init(app: AppContainer) {
        runner = ActionRunner(app: app)
        list = PagedListModel(app: app) { app, page, q, _ in
            try await app.service(MoneyAPI.self).receipts(page: page, q: q.trimmed.isEmpty ? nil : q)
        }
    }
}

/// /admin/receipts: every generated receipt, searchable, with delete.
struct ReceiptsScreen: View {
    var body: some View {
        WithModel({ MoneyReceiptsModel(app: $0) }) { MoneyReceiptsContent(model: $0) }
    }
}

private struct MoneyReceiptsContent: View {
    @Bindable var model: MoneyReceiptsModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        ManageListScreen(
            "Payment receipts", model: model.list, key: \.id, emptyTitle: "No receipts have been generated yet.",
            searchHint: "Receipt number, name, payment type or course"
        ) { r in
            RecordCard(
                title: r.invoiceNumber,
                subtitle: [r.user?.display, moneyCapitalized(r.paymentTypeLabel), r.courseTitle].compactMap { $0 }.joined(separator: " · "),
                meta: "\(money(r.amountInrPaise)) · \(formatDate(r.receiptGeneratedAt))",
                chip: r.receiptIncludesGst ? ("GST included", .success) : ("No GST", .neutral),
                onClick: { nav.push(.manage(.receipt(recordId: r.id))) },
                leading: { RowIcon(.receipt) },
                trailing: { IconButton(.delete, label: "Delete receipt", tint: Scheme.error) { model.deleting = r } }
            )
        }
        .reloadOnReturn { model.list.refresh() }
        .confirmDialog(
            item: $model.deleting, title: model.deleting.map { "Delete receipt \($0.invoiceNumber)?" } ?? "Delete receipt?",
            message: { _ in "The payment stays recorded; generating the receipt again later keeps the same receipt number." },
            confirm: "Delete", destructive: true
        ) { r in
            let list = model.list
            model.runner.run({ try await $0.service(MoneyAPI.self).deleteReceipt(r.id) }, success: "Receipt deleted successfully.") { _ in list.refresh() }
        }
    }
}

// MARK: - /admin/receipts/[paymentRecordId]

@MainActor
@Observable
final class MoneyReceiptModel {
    let recordId: String
    let loader: Loader<ReceiptDetail>
    let runner: ActionRunner
    var confirmDelete = false
    var confirmRegenerate = false

    init(app: AppContainer, recordId: String) {
        self.recordId = recordId
        loader = Loader(app: app) { try await $0.service(MoneyAPI.self).receipt(recordId).receipt }
        runner = ActionRunner(app: app)
    }

    func openPdf(_ invoiceNumber: String) {
        let id = recordId
        let name = "\(invoiceNumber.replacingOccurrences(of: "/", with: "-")).pdf"
        runner.openFile { try await $0.service(MoneyAPI.self).receiptPdf(id, fileName: name) }
    }

    func email() {
        let id = recordId, loader = self.loader
        runner.run({ try await $0.service(MoneyAPI.self).emailReceipt(id) }, success: "Receipt sent. Ask the student to check their Inbox or Spam/Junk folder.") { _ in
            loader.reload()
        }
    }

    func generate() {
        let id = recordId, loader = self.loader
        runner.run({ try await $0.service(MoneyAPI.self).generateReceipt(id) }, success: "Receipt generated successfully.") { _ in loader.reload() }
    }

    func delete() {
        let id = recordId, loader = self.loader
        runner.run({ try await $0.service(MoneyAPI.self).deleteReceipt(id) }, success: "Receipt deleted successfully.") { _ in loader.reload() }
    }

    func regenerate() {
        let id = recordId, loader = self.loader, runner = self.runner
        // Two calls, so the second can fail after the first deleted the receipt: always show what is there now.
        runner.run({ try await $0.regenerateReceipt(id) }) { failure in
            loader.reload()
            runner.message(
                failure.map { "The old receipt was deleted, but a new one couldn't be issued (\($0)). Tap \"Generate Receipt\" to try again." }
                    ?? "Receipt regenerated."
            )
        }
    }
}

extension AppContainer {
    /// Deletes the receipt and issues a new one. Returns nil when both worked, or why generating failed after the
    /// delete (a failed delete throws as usual: nothing changed).
    func regenerateReceipt(_ recordId: String) async throws -> String? {
        let api = service(MoneyAPI.self)
        _ = try await api.deleteReceipt(recordId)
        return await mainApiCall { try await api.generateReceipt(recordId) }.error?.message
    }
}

/// /admin/receipts/[paymentRecordId]: the receipt of one payment: open the PDF, e-mail it, regenerate or delete it.
struct ReceiptDetailScreen: View {
    let recordId: String

    var body: some View {
        WithModel({ MoneyReceiptModel(app: $0, recordId: recordId) }) { MoneyReceiptContent(model: $0) }
    }
}

private struct MoneyReceiptContent: View {
    @Bindable var model: MoneyReceiptModel

    var body: some View {
        let runner = model.runner
        ManageScaffold("Payment receipt") {
            LoadedColumn(model.loader) { r in
                let generated = r.receiptGeneratedAt != nil && r.invoiceNumber != nil
                DetailCard(generated ? r.invoiceNumber : "No receipt yet") {
                    if r.voided { Banner("This payment has been voided.", tone: .warning) }
                    Field("Student", [r.user?.name, r.user?.email].compactMap { $0 }.joined(separator: "\n"))
                    Field("Course", r.courseTitle ?? "—")
                    Field("Payment", [r.paymentTypeLabel, r.description].compactMap { $0 }.joined(separator: " · "))
                    Field("Paid on", formatDate(r.paidAt))
                    Field("Method", moneyNilIfBlank([r.paymentMethod.map(moneyCapitalized), r.reference].compactMap { $0 }.joined(separator: " · ")), showEmpty: false)
                }
                DetailCard("Amount") {
                    if generated {
                        FieldRow(r.receiptIncludesGst ? "Fee (excl. GST)" : "Fee", money(r.receiptFeeAmountPaise ?? r.amountInrPaise))
                        if r.receiptIncludesGst { FieldRow("GST (18% inclusive)", money(r.receiptGstAmountPaise ?? 0)) }
                        if (r.receiptShippingAmountPaise ?? 0) > 0 { FieldRow("Shipping", money(r.receiptShippingAmountPaise ?? 0)) }
                    }
                    FieldRow("Total", money(r.amountInrPaise), strong: true)
                }
                if generated, let invoice = r.invoiceNumber {
                    DetailCard("Receipt") {
                        Field("Generated", formatDateTime(r.receiptGeneratedAt))
                        Field("E-mailed to the student", r.receiptEmailSentAt.map { formatDateTime($0) } ?? "Not yet")
                        MoneyFlowRow(spacing: 8, lineSpacing: 4) {
                            MoneyOutlinedButton("Open PDF", icon: .pdf, enabled: !runner.busy) { model.openPdf(invoice) }
                            MoneyOutlinedButton("Send via Email", icon: .mail, enabled: !runner.busy) { model.email() }
                            MoneyOutlinedButton("Regenerate", icon: .autorenew, enabled: !runner.busy && !r.voided) { model.confirmRegenerate = true }
                            MoneyOutlinedButton("Delete", icon: .delete, color: Scheme.error, enabled: !runner.busy) { model.confirmDelete = true }
                        }
                    }
                } else {
                    DetailCard("Receipt") {
                        Text("No receipt has been generated for this payment.").textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface)
                        PrimaryButton("Generate Receipt", enabled: !r.voided, loading: runner.busy) { model.generate() }
                    }
                }
            }
        }
        .reloadOnReturn { model.loader.reload() }
        .confirmDialog(
            "Delete this receipt?", message: "The payment stays recorded; generating the receipt again later keeps the same receipt number.",
            isPresented: $model.confirmDelete, confirm: "Delete", destructive: true
        ) { model.delete() }
        .confirmDialog(
            "Regenerate this receipt?", message: "The receipt is issued again with the current settings. It keeps its receipt number.",
            isPresented: $model.confirmRegenerate, confirm: "Regenerate"
        ) { model.regenerate() }
    }
}

/// nil for blank text (Kotlin's `ifBlank { null }`).
func moneyNilIfBlank(_ value: String) -> String? { value.trimmed.isEmpty ? nil : value }
