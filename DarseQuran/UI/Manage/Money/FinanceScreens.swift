import Observation
import SwiftUI

/*
 * /admin/finance and /admin/finance/bookstore (Android's ui/manage/money/FinanceScreens.kt): summaries for a date
 * range, a bar chart, filters, the lists and Excel exports.
 */

/// "Courses Finance | Book Store" switch at the top of both finance screens.
private struct MoneyFinanceSectionChips: View {
    let bookstore: Bool
    let onSwitch: () -> Void

    var body: some View {
        FilterChips(
            options: [FilterOption(nil, "Courses Finance"), FilterOption("bookstore", "Book Store")],
            selected: bookstore ? "bookstore" : nil
        ) { v in if (v == "bookstore") != bookstore { onSwitch() } }
    }
}

/// The search box above a finance list. [hint] changes with the tab, and the box starts over with it.
private struct MoneyListSearch: View {
    let query: String
    let hint: String
    let onSearch: (String) -> Void

    var body: some View {
        SearchField(initial: query, placeholder: hint, onSearch: onSearch).id(hint)
    }
}

private let moneyCountFormat: NumberFormatter = {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "en_US")
    f.numberStyle = .decimal
    return f
}()

// MARK: - /admin/finance

private struct MoneyFinanceMeta {
    let range: FinanceRange
    let summary: FinanceSummary
    let filtered: FilteredTotals
}

@MainActor
final class MoneyFinanceModel {
    fileprivate let meta: MoneyListExtras<MoneyFinanceMeta>
    let list: PagedListModel<MoneyRow>
    let options: Loader<FinanceOptions>
    let runner: ActionRunner
    let student: MoneyStudentFilterModel

    init(app: AppContainer) {
        let meta = MoneyListExtras<MoneyFinanceMeta>()
        self.meta = meta
        list = PagedListModel(app: app) { app, page, q, filter in
            let r = try await app.service(MoneyAPI.self).finance(page: page, q: q.trimmed.isEmpty ? nil : q, filters: moneyDecodeFilters(filter))
            meta.value = MoneyFinanceMeta(range: r.range, summary: r.summary, filtered: r.filtered)
            return Paged(data: r.data, totalCount: r.totalCount, page: r.page, pageSize: r.pageSize)
        }
        options = Loader(app: app) { try await $0.service(MoneyAPI.self).options() }
        runner = ActionRunner(app: app)
        student = MoneyStudentFilterModel(app: app)
    }
}

/// /admin/finance: income and expenses for a date range, with summary cards, filters, the filtered total, Excel
/// export and shortcuts to record a payment or an expense.
struct FinanceScreen: View {
    var body: some View {
        WithModel({ MoneyFinanceModel(app: $0) }) { MoneyFinanceContent(model: $0) }
    }
}

private struct MoneyFinanceContent: View {
    let model: MoneyFinanceModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let state = model.list.state
        let filters = moneyDecodeFilters(state.filter)
        let expenses = filters["tab"] == "expenses"
        ManageScaffold("Finance") {
            PagedListBody(
                model.list, searchHint: nil,
                emptyTitle: expenses ? "No expenses for these filters." : "No income records for these filters.",
                key: { $0.kind + $0.id },
                header: { header(state: state, filters: filters, expenses: expenses) }
            ) { row in
                if row.kind == "expense" {
                    MoneyExpenseCard(row: row, runner: model.runner) { model.list.refresh() }
                } else {
                    MoneyIncomeCard(row: row, runner: nil, canVoid: false)
                }
            }
        }
        .reloadOnReturn { model.list.refresh() }
    }

    @ViewBuilder
    private func header(state: PagedState<MoneyRow>, filters: [String: String], expenses: Bool) -> some View {
        let meta = model.meta.value
        let opts = model.options.state.value
        let filter = state.filter
        let onFilter: (String?) -> Void = { model.list.filter($0) }
        Text("Track student fee income and academy expenses. Summary totals use the selected date range.")
            .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant).frame(maxWidth: .infinity, alignment: .leading)
        MoneyDateRangeBar(range: meta?.range, filter: filter, onChange: onFilter)
        let s = meta?.summary ?? FinanceSummary()
        VStack(spacing: 10) {
            MoneyFigureGrid(figures: [
                MoneyFigure("Total income", money(s.incomeTotalPaise), .success),
                MoneyFigure("Total expenses", money(s.expenseTotalPaise), .danger),
                MoneyFigure("Net balance", money(s.netBalancePaise), s.netBalancePaise >= 0 ? .success : .danger),
            ])
            MoneyBarChart(bars: [
                MoneyBar("Income", s.incomeTotalPaise, Brand.success),
                MoneyBar("Expenses", s.expenseTotalPaise, Brand.danger),
                MoneyBar("Net balance", s.netBalancePaise, s.netBalancePaise >= 0 ? Brand.success : Brand.danger),
            ])
        }
        MoneyFinanceSectionChips(bookstore: false) { nav.replace(upTo: .manage(.finance), with: .manage(.bookstoreFinance)) }
            .frame(maxWidth: .infinity, alignment: .leading)
        FilterChips(options: [FilterOption(nil, "Income"), FilterOption("expenses", "Expense")], selected: expenses ? "expenses" : nil) {
            model.list.filter(moneyWithFilters(filter, ["tab": $0]))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        HStack(spacing: 8) {
            MoneyOutlinedButton("Export to Excel", icon: .downloadLine, enabled: !model.runner.busy, fullWidth: true) {
                var params = filters
                params["type"] = expenses ? "expenses" : "income"
                if !state.query.trimmed.isEmpty { params["q"] = state.query }
                model.runner.openMoneyExport(expenses ? "Course_Expenses.xlsx" : "Course_Income.xlsx", params)
            }
            MoneyCtaButton(expenses ? "Record expense" : "Record payment", icon: .add, fullWidth: true) {
                nav.push(.manage(.transactions(expense: expenses)))
            }
        }
        MoneyListSearch(
            query: state.query, hint: expenses ? "Search by description, category, or teacher" : "Search by student, course, or description"
        ) { model.list.search($0) }
        VStack(spacing: 8) {
            if !expenses {
                MoneyFilterDropdown(
                    label: "Course", allLabel: "All courses", options: (opts?.courses ?? []).map { ($0.id, $0.title) }, filter: filter, key: "courseId",
                    onChange: onFilter
                )
                // A search: a menu of every student grows without limit.
                MoneyStudentFilter(model: model.student, filter: filter, onChange: onFilter)
                MoneyFilterDropdown(
                    label: "Payment type", allLabel: "All types", options: (opts?.incomePaymentTypes ?? []).map { ($0.value, $0.label) }, filter: filter,
                    key: "paymentType", onChange: onFilter
                )
            } else {
                MoneyFilterDropdown(
                    label: "Category", allLabel: "All categories", options: (opts?.expenseCategories ?? []).map { ($0.value, $0.label) }, filter: filter,
                    key: "category", onChange: onFilter
                )
                if filters["category"] == "teacher_salary" {
                    MoneyFilterDropdown(
                        label: "Teacher", allLabel: "All teachers", options: (opts?.teachers ?? []).map { ($0.id, $0.name) }, filter: filter, key: "teacherId",
                        onChange: onFilter
                    )
                }
            }
        }
        let f = meta?.filtered ?? FilteredTotals()
        AppCard(padding: 14) {
            Text("FILTERED RESULTS").textStyle(Typo.labelSmall).foregroundStyle(Scheme.onSurfaceVariant)
            Spacer().frame(height: 6)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Total records").textStyle(Typo.labelMedium).foregroundStyle(Scheme.onSurfaceVariant)
                    Text(moneyCountFormat.string(from: NSNumber(value: f.recordCount)) ?? "\(f.recordCount)")
                        .textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Total amount").textStyle(Typo.labelMedium).foregroundStyle(Scheme.onSurfaceVariant)
                    Text(money(f.totalPaise)).textStyle(Typo.titleLarge).foregroundStyle(expenses ? Brand.danger : Brand.success)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - /admin/finance/bookstore

private struct MoneyBookstoreMeta {
    let range: FinanceRange
    let summary: BookstoreSummary
}

@MainActor
final class MoneyBookstoreFinanceModel {
    fileprivate let meta: MoneyListExtras<MoneyBookstoreMeta>
    let list: PagedListModel<BookFinanceRow>
    let runner: ActionRunner

    init(app: AppContainer) {
        let meta = MoneyListExtras<MoneyBookstoreMeta>()
        self.meta = meta
        list = PagedListModel(app: app) { app, page, q, filter in
            let r = try await app.service(MoneyAPI.self).bookstore(page: page, q: q.trimmed.isEmpty ? nil : q, filters: moneyDecodeFilters(filter))
            meta.value = MoneyBookstoreMeta(range: r.range, summary: r.summary)
            return Paged(data: r.data, totalCount: r.totalCount, page: r.page, pageSize: r.pageSize)
        }
        runner = ActionRunner(app: app)
    }
}

/// /admin/finance/bookstore: Book Store summary, the book sales report and the order finance report.
struct BookstoreFinanceScreen: View {
    var body: some View {
        WithModel({ MoneyBookstoreFinanceModel(app: $0) }) { MoneyBookstoreFinanceContent(model: $0) }
    }
}

private struct MoneyBookstoreFinanceContent: View {
    let model: MoneyBookstoreFinanceModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let state = model.list.state
        let filters = moneyDecodeFilters(state.filter)
        let orders = filters["view"] == "orders"
        ManageScaffold("Book Store finance") {
            PagedListBody(
                model.list, searchHint: nil, emptyTitle: orders ? "No orders for these filters." : "No books found.", key: { $0.kind + $0.id },
                header: { header(state: state, filters: filters, orders: orders) }
            ) { row in
                if row.kind == "order" { MoneyBookOrderFinanceCard(r: row) } else { MoneyBookSaleCard(r: row) }
            }
        }
        .reloadOnReturn { model.list.refresh() }
    }

    @ViewBuilder
    private func header(state: PagedState<BookFinanceRow>, filters: [String: String], orders: Bool) -> some View {
        let meta = model.meta.value
        let filter = state.filter
        Text("Track Book Store performance, inventory costs, and revenue.")
            .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant).frame(maxWidth: .infinity, alignment: .leading)
        MoneyDateRangeBar(range: meta?.range, filter: filter) { model.list.filter($0) }
        let s = meta?.summary ?? BookstoreSummary()
        VStack(spacing: 10) {
            MoneyFigureGrid(figures: [
                MoneyFigure("Total Books Procured", "\(s.totalBooksPurchased)"),
                MoneyFigure("Total Books Sold", "\(s.totalBooksSold)"),
                MoneyFigure("Current Inventory", "\(s.currentInventoryCount)"),
                MoneyFigure("Average Order Value", money(s.averageOrderValuePaise)),
                MoneyFigure("Total Purchase Cost", money(s.totalPurchaseCostPaise), .danger),
                MoneyFigure("Book Sales Revenue", money(s.totalSalesRevenuePaise), .success, note: "Excludes shipping"),
                MoneyFigure("Shipping Collected", money(s.totalShippingCollectedPaise), note: "Passed on to the courier"),
                MoneyFigure("Total Profit / Loss", money(s.totalProfitLossPaise), s.totalProfitLossPaise >= 0 ? .success : .danger),
                MoneyFigure("Pending Orders Value", money(s.pendingOrdersValuePaise), .warning),
                MoneyFigure("Approved Orders Value", money(s.approvedOrdersValuePaise), .success),
                MoneyFigure("Completed Orders Value", money(s.completedOrdersValuePaise), .info),
            ])
            MoneyBarChart(bars: [
                MoneyBar("Purchase cost", s.totalPurchaseCostPaise, Brand.danger),
                MoneyBar("Sales revenue", s.totalSalesRevenuePaise, Brand.success),
                MoneyBar("Profit / loss", s.totalProfitLossPaise, s.totalProfitLossPaise >= 0 ? Brand.success : Brand.danger),
            ])
        }
        MoneyFinanceSectionChips(bookstore: true) { nav.replace(upTo: .manage(.bookstoreFinance), with: .manage(.finance)) }
            .frame(maxWidth: .infinity, alignment: .leading)
        FilterChips(options: [FilterOption(nil, "Book Sales Report"), FilterOption("orders", "Order Finance Report")], selected: orders ? "orders" : nil) {
            model.list.filter(moneyWithFilters(filter, ["view": $0]))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        MoneyListSearch(query: state.query, hint: orders ? "Search by order ID, customer name, or email" : "Search by book title or author") {
            model.list.search($0)
        }
        MoneyOutlinedButton("Export to Excel", icon: .downloadLine, enabled: !model.runner.busy, fullWidth: true) {
            var params = filters
            params.removeValue(forKey: "view")
            params["type"] = orders ? "book_orders" : "book_sales"
            if !state.query.trimmed.isEmpty { params["q"] = state.query }
            model.runner.openMoneyExport(orders ? "Bookstore_Order_Finance.xlsx" : "Book_Sales_Report.xlsx", params)
        }
    }
}

private struct MoneyBookSaleCard: View {
    let r: BookFinanceRow

    var body: some View {
        AppCard(padding: 14) {
            Text(r.title ?? "").textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurface)
            Text(r.author ?? "").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
            Spacer().frame(height: 6)
            MoneyInfoLine("Purchase price", money(r.purchasePriceInrPaise))
            MoneyInfoLine("Selling price", money(r.sellingPriceInrPaise))
            MoneyInfoLine("Procured", "\(r.quantityPurchased)")
            MoneyInfoLine("Sold", "\(r.quantitySold)")
            MoneyInfoLine("Stock", "\(r.remainingStock)")
            HStack(alignment: .center) {
                Text("Revenue \(money(r.revenuePaise))").textStyle(Typo.labelLarge).foregroundStyle(Brand.success)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Profit \(money(r.profitPaise))").textStyle(Typo.labelLarge).foregroundStyle(r.profitPaise >= 0 ? Brand.success : Brand.danger)
            }
            .padding(.top, 6)
        }
    }
}

private struct MoneyBookOrderFinanceCard: View {
    let r: BookFinanceRow

    var body: some View {
        let status = moneyStatus(r.status, label: r.statusLabel)
        AppCard(padding: 14) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(r.orderNumber.map { "#\($0) · " } ?? "")\(formatDate(r.orderDate))").textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurface)
                    Text(r.customerName ?? "").textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface)
                    Text(r.customerEmail ?? "").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(money(r.totalAmountPaise)).textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface)
            }
            Spacer().frame(height: 6)
            StatusChip(status.0, tone: status.1)
            Spacer().frame(height: 6)
            MoneyInfoLine("Address", r.deliveryAddress)
            MoneyInfoLine("PIN", r.deliveryPinCode)
            MoneyInfoLine("Phone", r.deliveryPhoneNumber)
            MoneyInfoLine("Shipping", money(r.shippingChargePaise))
            if r.refundedAmountPaise > 0 { MoneyInfoLine("Refunded", money(r.refundedAmountPaise)) }
            MoneyInfoLine("Profit", money(r.profitContributionPaise))
        }
    }
}
