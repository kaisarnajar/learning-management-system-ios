import Observation
import SwiftUI

/*
 * /admin/transactions (Android's ui/manage/money/TransactionsScreens.kt): record a payment received outside the app,
 * or an expense.
 */

@MainActor
@Observable
final class MoneyTransactionsModel {
    var expenseTab: Bool
    let options: Loader<FinanceOptions>
    let runner: ActionRunner
    let reset = FormReset()

    init(app: AppContainer, expense: Bool) {
        expenseTab = expense
        options = Loader(app: app) { try await $0.service(MoneyAPI.self).options() }
        runner = ActionRunner(app: app)
    }
}

/// /admin/transactions: record a payment received outside the app, or an expense. [expense] picks the tab.
struct TransactionsScreen: View {
    let expense: Bool

    var body: some View {
        WithModel({ MoneyTransactionsModel(app: $0, expense: expense) }) { MoneyTransactionsContent(model: $0) }
    }
}

private struct MoneyTransactionsContent: View {
    let model: MoneyTransactionsModel

    var body: some View {
        ManageScaffold("Record transactions") {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Manually log payments received from students or operational expenses.")
                        .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                    FilterChips(
                        options: [FilterOption(nil, "Record Payment"), FilterOption("expenses", "Record Expense")],
                        selected: model.expenseTab ? "expenses" : nil
                    ) { model.expenseTab = $0 == "expenses" }
                    switch model.options.state {
                    case .failed(let message):
                        ErrorState(message: message) { model.options.load() }
                    case .loading:
                        Text("Loading…").textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurface)
                    case .ready(let opts):
                        Group {
                            if model.expenseTab {
                                MoneyRecordExpenseForm(opts: opts, runner: model.runner, reset: model.reset)
                            } else {
                                WithModel({ app in
                                    AccountCheck(app: app) { app, email in
                                        AccountAnswer(try await app.service(MoneyAPI.self).lookupStudent(email: email).student.name)
                                    }
                                }) { account in
                                    MoneyRecordPaymentForm(opts: opts, runner: model.runner, reset: model.reset, account: account)
                                }
                            }
                        }
                        .id(model.reset.generation)
                    }
                    Spacer().frame(height: 24)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

private struct MoneyRecordPaymentForm: View {
    let opts: FinanceOptions
    let runner: ActionRunner
    let reset: FormReset
    let account: AccountCheck
    @State private var amount = ""
    @State private var paidAt: String
    @State private var type = "monthly"
    @State private var courseId = ""

    init(opts: FinanceOptions, runner: ActionRunner, reset: FormReset, account: AccountCheck) {
        self.opts = opts
        self.runner = runner
        self.reset = reset
        self.account = account
        _paidAt = State(initialValue: opts.today)
    }

    var body: some View {
        // The website looks the account up when the e-mail field loses focus; here, shortly after typing stops.
        let canSubmit = account.error == nil && (account.email.trimmed.isEmpty || account.verified)
        VStack(alignment: .leading, spacing: 16) {
            FormTextField("Registered account email", text: account.emailBinding, supporting: "student@example.com", keyboard: .email)
            if let error = account.error { Banner(error, tone: .warning) }
            FormTextField(
                "Name (from account)",
                text: .constant(
                    account.checking ? "Checking account…" : !account.name.isEmpty ? account.name : "Enter an email above to load the account name."
                ),
                enabled: false
            )
            FormMoneyField("Amount (₹)", text: $amount)
            FormDateField("Payment date", value: paidAt) { paidAt = $0 }
            FormDropdown("Type", options: opts.recordPaymentTypes.map { ($0.value, $0.label) }, value: type) { type = $0 }
            FormDropdown(
                "Course (optional)", options: [(value: "", label: "— General / not course-specific —")] + opts.courses.map { ($0.id, $0.title) },
                value: courseId, placeholder: "— General / not course-specific —"
            ) { courseId = $0 }
            PrimaryButton("Add payment", enabled: canSubmit && !account.email.trimmed.isEmpty, loading: runner.busy) {
                let form = formOf { f in
                    f.text("email", account.email.trimmed); f.text("amountInr", amount); f.text("paidAt", paidAt)
                    f.text("paymentType", type); f.text("courseId", courseId)
                }
                let reset = self.reset
                runner.run({ try await $0.service(MoneyAPI.self).recordPayment(form) }, success: "Transaction recorded successfully.") { _ in reset.reset() }
            }
        }
        .task(id: account.email) {
            if account.email.trimmed.isEmpty || account.verified { return }
            try? await Task.sleep(for: .milliseconds(700))
            if Task.isCancelled { return }
            account.verify()
        }
    }
}

private struct MoneyRecordExpenseForm: View {
    let opts: FinanceOptions
    let runner: ActionRunner
    let reset: FormReset
    @State private var category: String
    @State private var note = ""
    @State private var teacherId = ""
    @State private var amount = ""
    @State private var paidAt: String
    @State private var description = ""

    init(opts: FinanceOptions, runner: ActionRunner, reset: FormReset) {
        self.opts = opts
        self.runner = runner
        self.reset = reset
        _category = State(initialValue: opts.expenseCategories.first?.value ?? "teacher_salary")
        _paidAt = State(initialValue: opts.today)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FormDropdown("Category", options: opts.expenseCategories.map { ($0.value, $0.label) }, value: category) { category = $0 }
            if category == "other" {
                FormTextField("Specify category *", text: $note, supporting: "e.g. Printing, travel", maxLength: 100)
            }
            if category == "teacher_salary" {
                FormDropdown("Teacher", options: opts.teachers.map { ($0.id, $0.name) }, value: teacherId, placeholder: "Select teacher") { teacherId = $0 }
            }
            FormMoneyField("Amount (₹)", text: $amount)
            FormDateField("Payment date", value: paidAt) { paidAt = $0 }
            FormTextField("Description (optional)", text: $description, supporting: "e.g. March salary, domain renewal", maxLength: 500)
            PrimaryButton("Record expense", loading: runner.busy) {
                let category = self.category, note = self.note, teacherId = self.teacherId
                let form = formOf { f in
                    f.text("category", category); f.text("amountInr", amount); f.text("paidAt", paidAt); f.text("description", description)
                    if category == "other" { f.text("note", note) }
                    if category == "teacher_salary" { f.text("teacherId", teacherId) }
                }
                let reset = self.reset
                runner.run({ try await $0.service(MoneyAPI.self).recordExpense(form) }, success: "Transaction recorded successfully.") { _ in reset.reset() }
            }
        }
    }
}
