import Observation
import SwiftUI

/*
 * /admin/payment-settings and /admin/shipping-charges (Android's ui/manage/money/SettingsScreens.kt).
 */

// MARK: - /admin/payment-settings

@MainActor
@Observable
final class MoneyPaymentSettingsModel {
    let loader: Loader<AdminPaymentSettings>
    let runner: ActionRunner
    /// The fields hold the loaded settings (Save stays off until then, so it can't blank them).
    private(set) var ready = false
    var upiId = ""
    var upiNumber = ""
    var payee = ""
    var accountName = ""
    var bankName = ""
    var accountNumber = ""
    var ifsc = ""
    var branch = ""
    var gst = false
    var waivers = false
    var autoApprove = false

    init(app: AppContainer) {
        loader = Loader(app: app) { try await $0.service(MoneyAPI.self).settings().settings }
        runner = ActionRunner(app: app)
    }

    /// Fills the fields once, from the first settings loaded.
    func fillIfLoaded() {
        guard !ready, let s = loader.state.value else { return }
        upiId = s.upiId; upiNumber = s.upiNumber; payee = s.upiPayeeName
        accountName = s.bankAccountName; bankName = s.bankName; accountNumber = s.bankAccountNumber
        ifsc = s.bankIfsc; branch = s.bankBranch
        gst = s.includeGstByDefault; waivers = s.feeWaiverEnabled; autoApprove = s.autoApproveFullWaivers
        ready = true
    }

    func save() {
        let form = formOf { f in
            f.text("upiId", upiId); f.text("upiNumber", upiNumber); f.text("upiPayeeName", payee)
            f.text("bankAccountName", accountName); f.text("bankName", bankName); f.text("bankAccountNumber", accountNumber)
            f.text("bankIfsc", ifsc); f.text("bankBranch", branch)
            f.check("includeGstByDefault", gst); f.check("feeWaiverEnabled", waivers); f.check("autoApproveFullWaivers", autoApprove)
        }
        let loader = self.loader
        runner.run({ try await $0.service(MoneyAPI.self).saveSettings(form) }, success: "Payment details saved.") { _ in loader.reload() }
    }
}

/// /admin/payment-settings: UPI and bank details shown to students when they pay, and the receipt / waiver switches.
struct PaymentSettingsScreen: View {
    var body: some View {
        WithModel({ MoneyPaymentSettingsModel(app: $0) }) { MoneyPaymentSettingsContent(model: $0) }
    }
}

private struct MoneyPaymentSettingsContent: View {
    @Bindable var model: MoneyPaymentSettingsModel

    var body: some View {
        let loadError: String? = if case .failed(let message) = model.loader.state { message } else { nil }
        FormScreen(
            "Payment details", saving: model.runner.busy, saveLabel: "Save payment details", canSave: model.ready, loadError: loadError,
            onRetry: { model.loader.load() }, onSave: { model.save() }
        ) {
            if !model.ready {
                Text("Loading…").textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurface)
            } else {
                Text("UPI and bank information shown to students when paying course fees. Configure these before students enroll or pay monthly fees.")
                    .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                FormSection("UPI", description: "Shown on student payment pages and used for QR codes.") {
                    FormTextField("UPI ID", text: $model.upiId, supporting: "yourname@bank", capitalization: .never)
                    FormTextField("UPI Number (optional)", text: $model.upiNumber, supporting: "e.g. 9876543210", keyboard: .phone)
                    FormTextField("Payee name", text: $model.payee)
                }
                FormSection("Bank transfer", description: "Displayed alongside UPI for NEFT / IMPS / RTGS.") {
                    FormTextField("Account name", text: $model.accountName)
                    FormTextField("Bank name", text: $model.bankName)
                    FormTextField("Account number", text: $model.accountNumber, keyboard: .number)
                    FormTextField("IFSC code", text: Binding(get: { model.ifsc }, set: { model.ifsc = $0.uppercased() }), capitalization: .characters)
                    FormTextField("Branch (optional)", text: $model.branch)
                }
                FormSection("Receipt Settings", description: "Configure defaults for newly generated payment receipts.") {
                    FormSwitch("Include GST (18% inclusive) by default in generated receipts", checked: model.gst) { model.gst = $0 }
                    FormSwitch("Enable Fee Waiver & Coupon System", checked: model.waivers) { model.waivers = $0 }
                    FormSwitch("Auto-approve 100% fee waivers", checked: model.autoApprove, description: "Skip admin confirmation for fully waived fees") {
                        model.autoApprove = $0
                    }
                }
            }
        }
        .task(id: model.loader.state.value != nil) { model.fillIfLoaded() }
    }
}

// MARK: - /admin/shipping-charges

@MainActor
@Observable
final class MoneyShippingModel {
    let loader: Loader<[ShippingSlab]>
    let runner: ActionRunner
    var deleting: ShippingSlab?
    var min = ""
    var max = ""
    var charge = ""

    init(app: AppContainer) {
        loader = Loader(app: app) { try await $0.service(MoneyAPI.self).slabs().slabs }
        runner = ActionRunner(app: app)
    }

    func add() {
        let form = formOf { f in f.text("minWeightGrams", min); f.text("maxWeightGrams", max); f.text("chargeInr", charge) }
        runner.run({ try await $0.service(MoneyAPI.self).addSlab(form) }, success: "Shipping slab added.") { [weak self] _ in
            guard let self else { return }
            self.min = ""; self.max = ""; self.charge = ""
            self.loader.reload()
        }
    }

    func delete(_ slab: ShippingSlab) {
        let loader = self.loader
        runner.run({ try await $0.service(MoneyAPI.self).deleteSlab(slab.id) }, success: "Shipping slab deleted.") { _ in loader.reload() }
    }
}

/// /admin/shipping-charges: weight slabs and their charges; add and delete.
struct ShippingChargesScreen: View {
    var body: some View {
        WithModel({ MoneyShippingModel(app: $0) }) { MoneyShippingContent(model: $0) }
    }
}

private struct MoneyShippingContent: View {
    @Bindable var model: MoneyShippingModel

    var body: some View {
        ManageScaffold("Shipping charges") {
            LoadedColumn(model.loader) { slabs in
                Text(
                    "Configure shipping charges based on order weight. Slabs must be contiguous starting from 0 g. An order heavier than the highest slab pays the highest slab's charge; an order lighter than the lowest slab (for example books without a recorded weight) pays the lowest slab's charge."
                )
                .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                Text("CURRENT SLABS").textStyle(Typo.labelMedium).foregroundStyle(Scheme.onSurfaceVariant)
                if slabs.isEmpty {
                    Text("No shipping slabs configured yet.").textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface)
                }
                ForEach(slabs) { slab in
                    RecordCard(
                        title: "\(slab.minWeightGrams) g – \(slab.maxWeightGrams) g",
                        subtitle: formatInr(Int64(slab.chargeInrPaise), exact: true),
                        leading: { RowIcon(.localShipping) },
                        trailing: { IconButton(.delete, label: "Delete slab", tint: Scheme.error) { model.deleting = slab } }
                    )
                }
                DetailCard("Add new slab") {
                    HStack(alignment: .top, spacing: 8) {
                        FormNumberField("Min weight (g)", text: $model.min).frame(maxWidth: .infinity)
                        FormNumberField("Max weight (g)", text: $model.max).frame(maxWidth: .infinity)
                    }
                    FormMoneyField("Charge (₹)", text: $model.charge)
                    PrimaryButton(
                        "Add slab", enabled: !model.min.trimmed.isEmpty && !model.max.trimmed.isEmpty && !model.charge.trimmed.isEmpty,
                        loading: model.runner.busy
                    ) { model.add() }
                }
            }
        }
        .reloadOnReturn { model.loader.reload() }
        .confirmDialog(
            item: $model.deleting, title: model.deleting.map { "Delete slab \($0.minWeightGrams)-\($0.maxWeightGrams)g?" } ?? "Delete slab?",
            message: { _ in "Orders in this weight range would no longer have a matching slab. Delete slabs from the top down, or add a replacement first." },
            confirm: "Delete", destructive: true
        ) { model.delete($0) }
    }
}
