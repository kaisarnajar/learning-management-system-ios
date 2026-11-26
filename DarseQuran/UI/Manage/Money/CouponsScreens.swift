import Observation
import SwiftUI

/*
 * /admin/coupons and /admin/coupons/finance (Android's ui/manage/money/CouponsScreens.kt): fee-waiver requests, the
 * special and default coupons, the coupon form, and the claimed waivers' finance.
 */

private let moneyCouponTabs = [
    FilterOption(nil, "Waiver Requests"),
    FilterOption("special", "Special Coupons"),
    FilterOption("default", "Default Coupons"),
]

private let moneyApplyToOptions: [(value: String, label: String)] = [
    ("BOTH", "Both Enrollment & Course Fees"), ("ENROLLMENT", "Enrollment Fee Only"), ("COURSE", "Course Fee Only"),
]
private let moneyGenderOptions: [(value: String, label: String)] = [("", "All Genders"), ("MALE", "Male"), ("FEMALE", "Female")]

private let moneyMonospace = "Menlo-Regular"
private let moneyMonospaceBold = "Menlo-Bold"

// MARK: - /admin/coupons

@MainActor
@Observable
final class MoneyCouponsModel {
    /// nil: waiver requests; "special" or "default": that kind of coupon.
    private(set) var tab: String?
    let requests: PagedListModel<AdminWaiverRequest>
    let coupons: PagedListModel<CouponRow>
    let runner: ActionRunner

    init(app: AppContainer) {
        requests = PagedListModel(app: app) { app, page, _, status in try await app.service(MoneyAPI.self).waiverRequests(page: page, status: status) }
        coupons = PagedListModel(app: app) { app, page, _, type in
            let r = try await app.service(MoneyAPI.self).coupons(type: type == "special" ? "SPECIAL" : "DEFAULT", page: page)
            return Paged(data: r.data, totalCount: r.totalCount, page: r.page, pageSize: r.pageSize)
        }
        runner = ActionRunner(app: app)
    }

    func select(_ value: String?) {
        tab = value
        if let value, coupons.state.filter != value { coupons.filter(value) }
    }

    func refreshAll() { requests.refresh(); coupons.refresh() }
}

/// /admin/coupons: fee-waiver requests (approve, reject, delete) and the special and default coupons.
struct CouponsScreen: View {
    var body: some View {
        WithModel({ MoneyCouponsModel(app: $0) }) { MoneyCouponsContent(model: $0) }
    }
}

private struct MoneyCouponsContent: View {
    let model: MoneyCouponsModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let tab = model.tab
        ManageScaffold(
            "Fee waivers & coupons",
            actions: { IconButton(.insights, label: "Fee waiver finance") { nav.push(.manage(.waiverFinance)) } },
            fab: {
                if tab == "default" { AddFab("New coupon") { nav.push(.manage(.couponForm(CouponFormRoute()))) } }
            }
        ) {
            if tab == nil {
                PagedListBody(model.requests, searchHint: nil, emptyTitle: "No fee waiver requests found.", key: \.id, header: { header }) { r in
                    MoneyWaiverRequestCard(r: r, runner: model.runner) { model.refreshAll() }
                }
            } else {
                PagedListBody(
                    model.coupons, searchHint: nil, emptyTitle: tab == "special" ? "No special coupons created yet." : "No default coupons created yet.",
                    key: \.id, header: { header }
                ) { c in
                    MoneyCouponCard(c: c, runner: model.runner, onEdit: { nav.push(.manage(.couponForm(c.moneyFormRoute))) }) { model.coupons.refresh() }
                }
            }
        }
        .reloadOnReturn { model.refreshAll() }
    }

    @ViewBuilder private var header: some View {
        let tab = model.tab
        VStack(alignment: .leading, spacing: 0) {
            Text("Manage default discount coupons and special student waiver requests.")
                .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
            Spacer().frame(height: 8)
            FilterChips(options: moneyCouponTabs, selected: tab) { model.select($0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if tab == nil {
            FilterChips(
                options: [FilterOption(nil, "All"), FilterOption("PENDING", "Pending"), FilterOption("APPROVED", "Approved"), FilterOption("REJECTED", "Rejected")],
                selected: model.requests.state.filter
            ) { model.requests.filter($0) }
        }
        if tab == "special" {
            Text("Coupons generated for specific students or approved fee waiver requests.")
                .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant).frame(maxWidth: .infinity, alignment: .leading)
        }
        if tab == "default" {
            Text("General promotional coupons available to public or specific course/gender groups.")
                .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MoneyWaiverRequestCard: View {
    let r: AdminWaiverRequest
    let runner: ActionRunner
    let onChanged: () -> Void
    @State private var approving = false
    @State private var rejecting = false
    @State private var deleting = false

    var body: some View {
        let status = moneyStatus(r.status)
        AppCard(padding: 14) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(r.user?.name ?? r.user?.email ?? "").textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurface)
                    Text(r.user?.email ?? "").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                    if let whatsapp = r.user?.whatsapp, !whatsapp.trimmed.isEmpty {
                        Text("WhatsApp \(whatsapp)").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StatusChip(status.0, tone: status.1)
            }
            Spacer().frame(height: 6)
            MoneyInfoLine("Date", formatDate(r.createdAt))
            MoneyInfoLine("Course", r.courseTitle)
            MoneyInfoLine("Fee type", r.feeTypeLabel)
            Spacer().frame(height: 4)
            Text(r.reason).textStyle(Typo.bodySmall.with(name: moneyMonospace)).foregroundStyle(Scheme.onSurface)
            Spacer().frame(height: 8)
            MoneyFlowRow(spacing: 8, lineSpacing: 0) {
                if r.status == "PENDING" {
                    MoneyCtaButton("Approve", enabled: !runner.busy) { approving = true }
                    MoneyOutlinedButton("Reject", color: Scheme.error, enabled: !runner.busy) { rejecting = true }
                }
                if r.status != "APPROVED" { BarTextButton("Delete", enabled: !runner.busy, color: Scheme.error) { deleting = true } }
            }
        }
        .materialDialog(isPresented: $approving) {
            MoneyApproveWaiverDialog(onDismiss: { approving = false }) { percentage, validUntil in
                let id = r.id
                runner.run({
                    try await $0.service(MoneyAPI.self).approveRequest(id, formOf { f in f.text("percentage", percentage); f.text("validUntil", validUntil) })
                }, success: "Fee waiver request approved and coupon created.") { _ in onChanged() }
            }
        }
        .confirmDialog(
            "Reject fee waiver request", message: "Are you sure you want to reject this request? The student is notified.", isPresented: $rejecting,
            confirm: "Reject", destructive: true
        ) {
            runner.run({ try await $0.service(MoneyAPI.self).rejectRequest(r.id) }, success: "Fee waiver request rejected.") { _ in onChanged() }
        }
        .confirmDialog(
            "Delete this waiver request?",
            message: "The request for \(r.user?.name ?? "the student") is removed, with its unused coupon. This cannot be undone.", isPresented: $deleting,
            confirm: "Delete", destructive: true
        ) {
            runner.run({ try await $0.service(MoneyAPI.self).deleteRequest(r.id) }, success: "Waiver request deleted.") { _ in onChanged() }
        }
    }
}

/// The day [days] after today at the academy, as YYYY-MM-DD (`academyToday().plusDays(days)`).
func moneyAcademyDayIso(plusDays days: Int, now: Date = Date()) -> String {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    guard let today = parseIsoDate(academyTodayIso(now: now)), let later = utc.date(byAdding: .day, value: days, to: today) else {
        return academyTodayIso(now: now)
    }
    return isoDateString(later)
}

/// "Approve fee waiver": the discount and how long the coupon is valid.
private struct MoneyApproveWaiverDialog: View {
    let onDismiss: () -> Void
    let onApprove: (_ percentage: String, _ validUntil: String) -> Void
    @State private var percentage = "100"
    @State private var validUntil = moneyAcademyDayIso(plusDays: 30)

    var body: some View {
        DialogTitle("Approve fee waiver")
        VStack(alignment: .leading, spacing: 12) {
            FormNumberField(
                "Discount percentage (%)", text: Binding(get: { percentage }, set: { percentage = String($0.prefix(3)) }),
                supporting: "Set to 100 for a full free course/enrollment waiver."
            )
            FormDateField("Valid until", value: validUntil, supporting: "How long the student has to use this coupon.") { validUntil = $0 }
        }
        .backgroundStyle(Scheme.surfaceContainerHigh)
        .environment(\.fieldSurface, Scheme.surfaceContainerHigh)
        DialogButtons(
            dismissLabel: "Cancel", confirmLabel: "Approve & generate coupon",
            confirmEnabled: !percentage.trimmed.isEmpty && !validUntil.trimmed.isEmpty, onDismiss: onDismiss
        ) {
            onDismiss()
            onApprove(percentage, validUntil)
        }
    }
}

private struct MoneyCouponCard: View {
    let c: CouponRow
    let runner: ActionRunner
    let onEdit: () -> Void
    let onChanged: () -> Void
    @State private var deleting = false

    var body: some View {
        AppCard(padding: 14) {
            HStack(alignment: .center, spacing: 8) {
                Text(c.code).textStyle(Typo.titleMedium.with(name: moneyMonospaceBold)).foregroundStyle(Scheme.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(c.percentage)% OFF").textStyle(Typo.titleSmall).foregroundStyle(Brand.success)
            }
            Spacer().frame(height: 6)
            HStack(spacing: 6) {
                StatusChip(c.type, tone: c.type == "SPECIAL" ? .info : .neutral)
                StatusChip(c.isActive ? "Active" : "Inactive", tone: c.isActive ? .success : .warning)
            }
            Spacer().frame(height: 6)
            MoneyInfoLine("Created", c.createdAt.map { formatDate($0) } ?? "N/A")
            MoneyInfoLine("Valid", "\(formatCalendarDate(c.validFrom)) – \(formatCalendarDate(c.validUntil))")
            MoneyInfoLine("Course", c.courseTitle ?? "All Courses")
            MoneyInfoLine("Gender", c.gender.map { titleCase($0) })
            MoneyInfoLine("For", c.user.map { u in u.name.map { "\($0) (\(u.email))" } ?? u.email })
            MoneyInfoLine("Applies to", c.applyToLabel)
            HStack(spacing: 0) {
                Spacer()
                BarTextButton("Edit", enabled: !runner.busy, action: onEdit)
                BarTextButton("Delete", enabled: !runner.busy, color: Scheme.error) { deleting = true }
            }
        }
        .confirmDialog(
            "Delete \(c.code)?", message: "An unused coupon is deleted. A coupon that has been used is deactivated instead, to keep the payment history.",
            isPresented: $deleting, confirm: "Delete", destructive: true
        ) {
            let runner = self.runner
            runner.run({ try await $0.service(MoneyAPI.self).deleteCoupon(c.id) }) { res in
                runner.message(res.stringResult("success") ?? "Coupon deleted.")
                onChanged()
            }
        }
    }
}

extension CouponRow {
    /// The coupon form's arguments for editing this coupon.
    var moneyFormRoute: CouponFormRoute {
        CouponFormRoute(
            id: id, type: type, code: code, percentage: "\(percentage)", validFrom: dateOnly(validFrom), validUntil: dateOnly(validUntil),
            courseId: courseId ?? "", gender: gender ?? "", applyTo: applyTo, isActive: isActive
        )
    }
}

// MARK: - coupon form

@MainActor
@Observable
final class MoneyCouponFormModel {
    let route: CouponFormRoute
    let courses: Loader<[IdTitle]>
    let runner: ActionRunner
    var code: String
    var percentage: String
    var validFrom: String
    var validUntil: String
    var courseId: String
    var gender: String
    var applyTo: String
    var active: Bool

    var special: Bool { route.type == "SPECIAL" }

    init(app: AppContainer, route: CouponFormRoute) {
        self.route = route
        courses = Loader(app: app) { try await $0.service(MoneyAPI.self).coupons(type: "DEFAULT", page: 1).courses }
        runner = ActionRunner(app: app)
        code = route.code
        percentage = route.percentage
        validFrom = route.validFrom.trimmed.isEmpty ? academyTodayIso() : route.validFrom
        validUntil = route.validUntil
        courseId = route.courseId
        gender = route.gender
        applyTo = route.applyTo
        active = route.isActive
    }

    /// What Save sends: a special coupon only its discount, dates and active state.
    var form: FormBody {
        formOf { f in
            if !special { f.text("code", code.trimmed.uppercased()); f.text("courseId", courseId); f.text("gender", gender); f.text("applyTo", applyTo) }
            f.text("percentage", percentage); f.text("validFrom", validFrom); f.text("validUntil", validUntil)
            if active { f.text("isActive", "true") }
        }
    }

    func save(onSaved: @escaping @MainActor () -> Void) {
        let form = self.form, id = route.id
        runner.run({ app in
            if let id { try await app.service(MoneyAPI.self).updateCoupon(id, form) } else { try await app.service(MoneyAPI.self).createCoupon(form) }
        }, success: id == nil ? "Coupon created." : "Coupon updated.") { _ in onSaved() }
    }
}

/// Create a DEFAULT coupon (no [CouponFormRoute.id]) or edit one; a SPECIAL coupon only changes discount, dates and
/// active.
struct CouponFormScreen: View {
    let route: CouponFormRoute

    var body: some View {
        WithModel({ MoneyCouponFormModel(app: $0, route: route) }) { MoneyCouponFormContent(model: $0) }
    }
}

private struct MoneyCouponFormContent: View {
    @Bindable var model: MoneyCouponFormModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let isNew = model.route.id == nil
        let courseOptions = (model.courses.state.value ?? []).map { (value: $0.id, label: $0.title) }
        FormScreen(
            isNew ? "Create default coupon" : "Edit coupon", saving: model.runner.busy, saveLabel: isNew ? "Create coupon" : "Save changes",
            onSave: { model.save { nav.pop() } }
        ) {
            if model.special {
                Text("This coupon belongs to one student's approved waiver: only the discount, validity and active state can change.")
                    .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
            } else {
                FormTextField("Code", text: Binding(get: { model.code }, set: { model.code = $0.uppercased() }), capitalization: .characters)
            }
            FormNumberField("Discount percentage (%)", text: Binding(get: { model.percentage }, set: { model.percentage = String($0.prefix(3)) }))
            HStack(alignment: .top, spacing: 8) {
                FormDateField("Valid from", value: model.validFrom) { model.validFrom = $0 }.frame(maxWidth: .infinity)
                FormDateField("Valid until", value: model.validUntil) { model.validUntil = $0 }.frame(maxWidth: .infinity)
            }
            if !model.special {
                FormDropdown(
                    "Course (optional)", options: [(value: "", label: "All Courses")] + courseOptions, value: model.courseId, placeholder: "All Courses"
                ) { model.courseId = $0 }
                FormDropdown("Gender (optional)", options: moneyGenderOptions, value: model.gender, placeholder: "All Genders") { model.gender = $0 }
                FormDropdown("Applies to fee type", options: moneyApplyToOptions, value: model.applyTo) { model.applyTo = $0 }
            }
            if !isNew { FormCheckbox("Active", checked: model.active) { model.active = $0 } }
        }
    }
}

// MARK: - /admin/coupons/finance

private struct MoneyWaiverMeta {
    let range: FinanceRange
    let stats: WaiverStats
}

@MainActor
final class MoneyWaiverFinanceModel {
    fileprivate let meta: MoneyListExtras<MoneyWaiverMeta>
    let list: PagedListModel<WaiverItem>
    let options: Loader<FinanceOptions>
    let runner: ActionRunner
    let student: MoneyStudentFilterModel

    init(app: AppContainer) {
        let meta = MoneyListExtras<MoneyWaiverMeta>()
        self.meta = meta
        list = PagedListModel(app: app) { app, page, q, filter in
            let r = try await app.service(MoneyAPI.self).waiverFinance(page: page, q: q.trimmed.isEmpty ? nil : q, filters: moneyDecodeFilters(filter))
            meta.value = MoneyWaiverMeta(range: r.range, stats: r.stats)
            return Paged(data: r.data, totalCount: r.totalCount, page: r.page, pageSize: r.pageSize)
        }
        options = Loader(app: app) { try await $0.service(MoneyAPI.self).options() }
        runner = ActionRunner(app: app)
        student = MoneyStudentFilterModel(app: app)
    }
}

/// Claimed fee waivers: totals, filters and each waiver with its receipt.
struct WaiverFinanceScreen: View {
    var body: some View {
        WithModel({ MoneyWaiverFinanceModel(app: $0) }) { MoneyWaiverFinanceContent(model: $0) }
    }
}

private struct MoneyWaiverFinanceContent: View {
    let model: MoneyWaiverFinanceModel

    var body: some View {
        ManageScaffold("Fee waiver finance") {
            PagedListBody(
                model.list, searchHint: nil, emptyTitle: "No claimed fee waivers found for the selected filters.", key: \.id, header: { header }
            ) { w in
                MoneyWaiverItemCard(w: w, runner: model.runner) { model.list.refresh() }
            }
        }
        .reloadOnReturn { model.list.refresh() }
    }

    @ViewBuilder private var header: some View {
        let state = model.list.state
        let meta = model.meta.value
        let opts = model.options.state.value
        let filter = state.filter
        let onFilter: (String?) -> Void = { model.list.filter($0) }
        Text("Financial analytics and total claimed fee waivers across courses and students.")
            .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant).frame(maxWidth: .infinity, alignment: .leading)
        MoneyDateRangeBar(range: meta?.range, filter: filter, onChange: onFilter)
        let s = meta?.stats ?? WaiverStats()
        MoneyFigureGrid(figures: [
            MoneyFigure("Total Waivers Claimed", "\(s.totalWaiverCount)", note: "Original total: \(money(s.totalOriginalFeePaise))"),
            MoneyFigure("Total Sum Waived Off", money(s.totalSumWaivedPaise), .success, note: "Net collected: \(money(s.totalNetPaidPaise))"),
            MoneyFigure("100% Full Waivers", "\(s.fullWaiverCount)", note: "Waived: \(money(s.fullWaiverSumPaise))"),
            MoneyFigure("Partial Waivers", "\(s.partialWaiverCount)", note: "Waived: \(money(s.partialWaiverSumPaise))"),
        ])
        SearchField(initial: state.query, placeholder: "Student name, email, course, or label") { model.list.search($0) }
        VStack(spacing: 8) {
            MoneyFilterDropdown(
                label: "Course", allLabel: "All courses", options: (opts?.courses ?? []).map { ($0.id, $0.title) }, filter: filter, key: "courseId",
                onChange: onFilter
            )
            MoneyStudentFilter(model: model.student, filter: filter, onChange: onFilter)
            MoneyFilterDropdown(
                label: "Payment type", allLabel: "All types", options: (opts?.incomePaymentTypes ?? []).map { ($0.value, $0.label) }, filter: filter,
                key: "paymentType", onChange: onFilter
            )
        }
    }
}

private struct MoneyWaiverItemCard: View {
    let w: WaiverItem
    let runner: ActionRunner
    let onChanged: () -> Void

    var body: some View {
        AppCard(padding: 14) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(w.studentName).textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurface)
                    Text(w.studentEmail).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StatusChip("\(w.discountPercentage)% OFF", tone: .success)
            }
            Spacer().frame(height: 6)
            MoneyInfoLine("Date", formatDate(w.date))
            MoneyInfoLine("Course", w.courseTitle)
            MoneyInfoLine("Fee", moneyCapitalized(w.paymentType) + " fee")
            MoneyInfoLine("Original fee", money(w.originalFeePaise))
            MoneyInfoLine("Waived off", "-" + money(w.waivedAmountPaise))
            MoneyInfoLine("Net paid", money(w.netPaidPaise))
            if let recordId = w.paymentRecordId {
                Spacer().frame(height: 6)
                MoneyReceiptButton(recordId: recordId, generatedAt: w.receiptGeneratedAt, runner: runner, onGenerated: onChanged)
            }
        }
    }
}
