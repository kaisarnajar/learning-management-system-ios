import Foundation

/*
 * Money: pending and completed payments, receipts, finance, transactions, payment settings, shipping charges, coupons
 * and fee waivers (/api/v1/admin/…). Ported from Android's data/staff/money/MoneyApi.kt.
 *
 * Renamed where the student app already has the name: PaymentSettings → AdminPaymentSettings,
 * PaymentSettingsResponse → AdminPaymentSettingsResponse, WaiverRequest → AdminWaiverRequest, and this package's
 * PersonRef → MoneyPersonRef (people has its own). Android's money `Option(value, label)` is the app's `Option`.
 * Kotlin `Long` amounts are `Int64` (formatInr takes them as they are).
 */

struct IdTitle: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var title: String = ""
}

/// Android's money PersonRef (a student on the finance forms; the id is always there).
struct MoneyPersonRef: Model, Identifiable {
    var id: String
    var name: String? = nil
    @Default<Empty.Text> var email: String = ""
}

struct TeacherRef: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var name: String = ""
}

struct MoneyUser: Model {
    var id: String? = nil
    var name: String? = nil
    @Default<Empty.Text> var email: String = ""
    var whatsapp: String? = nil

    /// The name, or the e-mail when there is none.
    var display: String { name.flatMap { $0.trimmed.isEmpty ? nil : $0 } ?? email }
}

struct BookLine: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var title: String = ""
    @Default<Zero> var quantity: Int = 0
    @Default<Zero> var lineTotalPaise: Int = 0
}

/// One row of the payment lists. [kind] says which fields are set: "submission" (a student's fee payment),
/// "book_order", "income" (a payment record) or "expense".
struct MoneyRow: Model, Identifiable {
    @Default<Empty.Text> var kind: String = ""
    var id: String
    @Default<Zero> var amountInrPaise: Int = 0
    var user: MoneyUser? = nil
    var paymentRecordId: String? = nil
    var receiptGeneratedAt: String? = nil
    var courseTitle: String? = nil
    // fee submission
    var paymentType: String? = nil
    var label: String? = nil
    var status: String? = nil
    var paymentMethod: String? = nil
    var reference: String? = nil
    var screenshotPath: String? = nil
    @Default<False> var screenshotIsPdf: Bool = false
    var submittedAt: String? = nil
    var createdAt: String? = nil
    // book order
    var statusLabel: String? = nil
    var deliveryAddress: String? = nil
    var deliveryPinCode: String? = nil
    var deliveryPhoneNumber: String? = nil
    var courierServiceName: String? = nil
    var trackingId: String? = nil
    @Default<Empty.List<BookLine>> var items: [BookLine] = []
    @Default<False> var canVoid: Bool = false
    // payment record
    var paidAt: String? = nil
    var paymentTypeLabel: String? = nil
    var description: String? = nil
    // expense
    var category: String? = nil
    var categoryLabel: String? = nil
    var note: String? = nil
    var teacher: TeacherRef? = nil
}

struct PendingPayments: Model {
    @Default<Empty.List<MoneyRow>> var data: [MoneyRow] = []
    @Default<Zero> var totalCount: Int = 0
    @Default<One> var page: Int = 1
    @Default<Twenty> var pageSize: Int = 20
    @Default<Empty.Text> var type: String = ""
    @Default<EmptyCounts> var counts: [String: Int] = [:]
}

struct CompletedPayments: Model {
    @Default<Empty.List<MoneyRow>> var data: [MoneyRow] = []
    @Default<Zero> var totalCount: Int = 0
    @Default<One> var page: Int = 1
    @Default<Twenty> var pageSize: Int = 20
    @Default<Empty.Text> var type: String = ""
    @Default<Empty.List<Option>> var tabs: [Option] = []
}

// MARK: - receipts

struct ReceiptRow: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var invoiceNumber: String = ""
    var receiptGeneratedAt: String? = nil
    @Default<Empty.Text> var paymentTypeLabel: String = ""
    @Default<Zero> var amountInrPaise: Int = 0
    @Default<False> var receiptIncludesGst: Bool = false
    var user: MoneyUser? = nil
    var courseTitle: String? = nil
}

struct ReceiptDetail: Model, Identifiable {
    var id: String
    var invoiceNumber: String? = nil
    var receiptGeneratedAt: String? = nil
    var receiptEmailSentAt: String? = nil
    @Default<False> var receiptIncludesGst: Bool = false
    var receiptFeeAmountPaise: Int? = nil
    var receiptGstAmountPaise: Int? = nil
    var receiptShippingAmountPaise: Int? = nil
    @Default<Zero> var amountInrPaise: Int = 0
    var paidAt: String? = nil
    @Default<Empty.Text> var paymentTypeLabel: String = ""
    var description: String? = nil
    var paymentMethod: String? = nil
    var reference: String? = nil
    @Default<False> var voided: Bool = false
    var courseTitle: String? = nil
    var user: MoneyUser? = nil
}

struct ReceiptResponse: Model { var receipt: ReceiptDetail }

// MARK: - finance

struct FinanceRange: Model, Initable {
    @Default<ThisMonth> var preset: String = "this_month"
    var from: String? = nil
    var to: String? = nil
}

struct FinanceSummary: Model, Initable {
    @Default<ZeroLong> var incomeTotalPaise: Int64 = 0
    @Default<ZeroLong> var expenseTotalPaise: Int64 = 0
    @Default<ZeroLong> var netBalancePaise: Int64 = 0
}

struct FilteredTotals: Model, Initable {
    @Default<Zero> var recordCount: Int = 0
    @Default<ZeroLong> var totalPaise: Int64 = 0
}

struct FinanceResponse: Model {
    @Default<Empty.List<MoneyRow>> var data: [MoneyRow] = []
    @Default<Zero> var totalCount: Int = 0
    @Default<One> var page: Int = 1
    @Default<Twenty> var pageSize: Int = 20
    @Default<IncomeTab> var tab: String = "income"
    @Default<Fallback<FinanceRange>> var range: FinanceRange = FinanceRange()
    @Default<Fallback<FinanceSummary>> var summary: FinanceSummary = FinanceSummary()
    @Default<Fallback<FilteredTotals>> var filtered: FilteredTotals = FilteredTotals()
}

struct FinanceOptions: Model {
    @Default<Empty.List<IdTitle>> var courses: [IdTitle] = []
    @Default<Empty.List<MoneyPersonRef>> var students: [MoneyPersonRef] = []
    @Default<Empty.List<TeacherRef>> var teachers: [TeacherRef] = []
    @Default<Empty.List<Option>> var expenseCategories: [Option] = []
    @Default<Empty.List<Option>> var incomePaymentTypes: [Option] = []
    @Default<Empty.List<Option>> var recordPaymentTypes: [Option] = []
    @Default<Empty.List<Option>> var datePresets: [Option] = []
    @Default<Empty.Text> var today: String = ""
}

struct BookstoreSummary: Model, Initable {
    @Default<Zero> var totalBooksPurchased: Int = 0
    @Default<Zero> var totalBooksSold: Int = 0
    @Default<Zero> var currentInventoryCount: Int = 0
    @Default<ZeroLong> var totalPurchaseCostPaise: Int64 = 0
    @Default<ZeroLong> var totalSalesRevenuePaise: Int64 = 0
    @Default<ZeroLong> var totalShippingCollectedPaise: Int64 = 0
    @Default<ZeroLong> var totalProfitLossPaise: Int64 = 0
    @Default<ZeroLong> var pendingOrdersValuePaise: Int64 = 0
    @Default<ZeroLong> var approvedOrdersValuePaise: Int64 = 0
    @Default<ZeroLong> var completedOrdersValuePaise: Int64 = 0
    @Default<ZeroLong> var averageOrderValuePaise: Int64 = 0
}

/// A row of the Book Store reports: [kind] "sale" (one book) or "order".
struct BookFinanceRow: Model, Identifiable {
    @Default<Empty.Text> var kind: String = ""
    var id: String
    // sale
    var title: String? = nil
    var author: String? = nil
    @Default<Zero> var purchasePriceInrPaise: Int = 0
    @Default<Zero> var sellingPriceInrPaise: Int = 0
    @Default<Zero> var quantityPurchased: Int = 0
    @Default<Zero> var quantitySold: Int = 0
    @Default<Zero> var remainingStock: Int = 0
    @Default<ZeroLong> var revenuePaise: Int64 = 0
    @Default<ZeroLong> var profitPaise: Int64 = 0
    // order
    var orderNumber: String? = nil
    var orderDate: String? = nil
    var customerName: String? = nil
    var customerEmail: String? = nil
    var deliveryAddress: String? = nil
    var deliveryPinCode: String? = nil
    var deliveryPhoneNumber: String? = nil
    var status: String? = nil
    var statusLabel: String? = nil
    @Default<ZeroLong> var totalAmountPaise: Int64 = 0
    @Default<ZeroLong> var shippingChargePaise: Int64 = 0
    @Default<ZeroLong> var refundedAmountPaise: Int64 = 0
    @Default<ZeroLong> var profitContributionPaise: Int64 = 0
}

struct BookstoreFinanceResponse: Model {
    @Default<Empty.List<BookFinanceRow>> var data: [BookFinanceRow] = []
    @Default<Zero> var totalCount: Int = 0
    @Default<One> var page: Int = 1
    @Default<Twenty> var pageSize: Int = 20
    @Default<SalesView> var view: String = "sales"
    @Default<Fallback<FinanceRange>> var range: FinanceRange = FinanceRange()
    @Default<Fallback<BookstoreSummary>> var summary: BookstoreSummary = BookstoreSummary()
}

// MARK: - transactions

struct LookedUpStudent: Model {
    var userId: String
    @Default<Empty.Text> var name: String = ""
}

struct StudentLookup: Model { var student: LookedUpStudent }

// MARK: - settings

/// The academy's payment settings as the admin edits them (Android's money PaymentSettings).
struct AdminPaymentSettings: Model {
    @Default<Empty.Text> var upiId: String = ""
    @Default<Empty.Text> var upiNumber: String = ""
    @Default<Empty.Text> var upiPayeeName: String = ""
    @Default<Empty.Text> var bankAccountName: String = ""
    @Default<Empty.Text> var bankName: String = ""
    @Default<Empty.Text> var bankAccountNumber: String = ""
    @Default<Empty.Text> var bankIfsc: String = ""
    @Default<Empty.Text> var bankBranch: String = ""
    @Default<False> var includeGstByDefault: Bool = false
    @Default<False> var feeWaiverEnabled: Bool = false
    @Default<False> var autoApproveFullWaivers: Bool = false
}

/// Android's money PaymentSettingsResponse.
struct AdminPaymentSettingsResponse: Model { var settings: AdminPaymentSettings }

struct ShippingSlab: Model, Identifiable {
    var id: String
    @Default<Zero> var minWeightGrams: Int = 0
    @Default<Zero> var maxWeightGrams: Int = 0
    @Default<Zero> var chargeInrPaise: Int = 0
}

struct ShippingResponse: Model { @Default<Empty.List<ShippingSlab>> var slabs: [ShippingSlab] = [] }

// MARK: - fee waivers

struct CouponRow: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var code: String = ""
    @Default<DefaultCouponType> var type: String = "DEFAULT"
    @Default<Zero> var percentage: Int = 0
    var validFrom: String? = nil
    var validUntil: String? = nil
    var courseId: String? = nil
    var courseTitle: String? = nil
    var gender: String? = nil
    var user: MoneyUser? = nil
    @Default<True> var isActive: Bool = true
    @Default<ApplyToBoth> var applyTo: String = "BOTH"
    @Default<Empty.Text> var applyToLabel: String = ""
    var createdAt: String? = nil
}

struct CouponsResponse: Model {
    @Default<Empty.List<CouponRow>> var data: [CouponRow] = []
    @Default<Zero> var totalCount: Int = 0
    @Default<One> var page: Int = 1
    @Default<Twenty> var pageSize: Int = 20
    @Default<DefaultCouponType> var type: String = "DEFAULT"
    @Default<Empty.List<IdTitle>> var courses: [IdTitle] = []
}

/// A student's fee waiver request as the admin sees it (Android's money WaiverRequest).
struct AdminWaiverRequest: Model, Identifiable {
    var id: String
    var createdAt: String? = nil
    @Default<Empty.Text> var reason: String = ""
    @Default<Empty.Text> var feeTypeLabel: String = ""
    @Default<PendingUpper> var status: String = "PENDING"
    var couponId: String? = nil
    var user: MoneyUser? = nil
    @Default<Empty.Text> var courseTitle: String = ""
}

struct WaiverStats: Model, Initable {
    @Default<Zero> var totalWaiverCount: Int = 0
    @Default<ZeroLong> var totalSumWaivedPaise: Int64 = 0
    @Default<ZeroLong> var totalOriginalFeePaise: Int64 = 0
    @Default<ZeroLong> var totalNetPaidPaise: Int64 = 0
    @Default<Zero> var fullWaiverCount: Int = 0
    @Default<ZeroLong> var fullWaiverSumPaise: Int64 = 0
    @Default<Zero> var partialWaiverCount: Int = 0
    @Default<ZeroLong> var partialWaiverSumPaise: Int64 = 0
}

struct WaiverItem: Model, Identifiable {
    var id: String
    var date: String? = nil
    @Default<Empty.Text> var studentName: String = ""
    @Default<Empty.Text> var studentEmail: String = ""
    @Default<Empty.Text> var courseTitle: String = ""
    @Default<Empty.Text> var paymentType: String = ""
    @Default<Empty.Text> var label: String = ""
    @Default<Zero> var originalFeePaise: Int = 0
    @Default<Zero> var waivedAmountPaise: Int = 0
    @Default<Zero> var discountPercentage: Int = 0
    @Default<Zero> var netPaidPaise: Int = 0
    var paymentRecordId: String? = nil
    var receiptGeneratedAt: String? = nil
}

struct WaiverFinanceResponse: Model {
    @Default<Empty.List<WaiverItem>> var data: [WaiverItem] = []
    @Default<Zero> var totalCount: Int = 0
    @Default<One> var page: Int = 1
    @Default<Twenty> var pageSize: Int = 20
    @Default<Fallback<FinanceRange>> var range: FinanceRange = FinanceRange()
    @Default<Fallback<WaiverStats>> var stats: WaiverStats = WaiverStats()
}

// MARK: - API

struct MoneyAPI: StaffService {
    let client: APIClient

    private func merged(_ base: [String: String?], _ filters: [String: String]) -> [String: String?] {
        var query = base
        for (k, v) in filters { query[k] = v }
        return query
    }

    // /admin/payments
    func pending(type: String, page: Int, q: String?) async throws -> PendingPayments {
        try await client.get("admin/payments", query: ["type": type, "page": "\(page)", "q": q])
    }
    func approve(_ id: String) async throws -> ActionResponse { try await client.post("admin/payments/\(id.pathEncoded)/approve") }
    func decline(_ id: String) async throws -> ActionResponse { try await client.post("admin/payments/\(id.pathEncoded)/decline") }
    func voidPayment(_ id: String, _ form: FormBody) async throws -> ActionResponse { try await client.form("POST", "admin/payments/\(id.pathEncoded)/void", form) }

    // /admin/completed-payments
    func completed(type: String, page: Int, q: String?) async throws -> CompletedPayments {
        try await client.get("admin/completed-payments", query: ["type": type, "page": "\(page)", "q": q])
    }
    func voidRecord(_ id: String, _ form: FormBody) async throws -> ActionResponse { try await client.form("POST", "admin/payment-records/\(id.pathEncoded)/void", form) }
    func deleteExpense(_ id: String) async throws -> ActionResponse { try await client.delete("admin/expenses/\(id.pathEncoded)") }

    // /admin/receipts
    func receipts(page: Int, q: String?) async throws -> Paged<ReceiptRow> { try await client.get("admin/receipts", query: ["page": "\(page)", "q": q]) }
    func receipt(_ id: String) async throws -> ReceiptResponse { try await client.get("admin/receipts/\(id.pathEncoded)") }
    func generateReceipt(_ id: String) async throws -> ActionResponse { try await client.post("admin/receipts/\(id.pathEncoded)") }
    func deleteReceipt(_ id: String) async throws -> ActionResponse { try await client.delete("admin/receipts/\(id.pathEncoded)") }
    func emailReceipt(_ id: String) async throws -> ActionResponse { try await client.post("admin/receipts/\(id.pathEncoded)/email") }
    /// The receipt PDF, downloaded into the document cache as [fileName].
    func receiptPdf(_ id: String, fileName: String) async throws -> URL { try await client.download("admin/receipts/\(id.pathEncoded)/pdf", fileName: fileName) }

    // /admin/finance
    func finance(page: Int, q: String?, filters: [String: String]) async throws -> FinanceResponse {
        try await client.get("admin/finance", query: merged(["page": "\(page)", "q": q], filters))
    }
    func options() async throws -> FinanceOptions { try await client.get("admin/finance/options") }
    /// The finance export (an .xlsx workbook), downloaded into the document cache as [fileName].
    func export(_ params: [String: String], fileName: String) async throws -> URL {
        try await client.download("admin/finance/export", fileName: fileName, query: params.mapValues { Optional($0) })
    }
    func bookstore(page: Int, q: String?, filters: [String: String]) async throws -> BookstoreFinanceResponse {
        try await client.get("admin/finance/bookstore", query: merged(["page": "\(page)", "q": q], filters))
    }

    // /admin/transactions
    func lookupStudent(email: String) async throws -> StudentLookup { try await client.get("admin/transactions/student", query: ["email": email]) }
    func recordPayment(_ form: FormBody) async throws -> ActionResponse { try await client.form("POST", "admin/transactions/payments", form) }
    func recordExpense(_ form: FormBody) async throws -> ActionResponse { try await client.form("POST", "admin/transactions/expenses", form) }

    // /admin/payment-settings, /admin/shipping-charges
    func settings() async throws -> AdminPaymentSettingsResponse { try await client.get("admin/payment-settings") }
    func saveSettings(_ form: FormBody) async throws -> ActionResponse { try await client.form("PUT", "admin/payment-settings", form) }
    func slabs() async throws -> ShippingResponse { try await client.get("admin/shipping-charges") }
    func addSlab(_ form: FormBody) async throws -> ActionResponse { try await client.form("POST", "admin/shipping-charges", form) }
    func deleteSlab(_ id: String) async throws -> ActionResponse { try await client.delete("admin/shipping-charges/\(id.pathEncoded)") }

    // /admin/coupons
    func coupons(type: String, page: Int) async throws -> CouponsResponse { try await client.get("admin/coupons", query: ["type": type, "page": "\(page)"]) }
    func createCoupon(_ form: FormBody) async throws -> ActionResponse { try await client.form("POST", "admin/coupons", form) }
    func updateCoupon(_ id: String, _ form: FormBody) async throws -> ActionResponse { try await client.form("PATCH", "admin/coupons/\(id.pathEncoded)", form) }
    func deleteCoupon(_ id: String) async throws -> ActionResponse { try await client.delete("admin/coupons/\(id.pathEncoded)") }
    func waiverRequests(page: Int, status: String?) async throws -> Paged<AdminWaiverRequest> {
        try await client.get("admin/coupons/requests", query: ["page": "\(page)", "status": status])
    }
    func approveRequest(_ id: String, _ form: FormBody) async throws -> ActionResponse { try await client.form("POST", "admin/coupons/requests/\(id.pathEncoded)/approve", form) }
    func rejectRequest(_ id: String) async throws -> ActionResponse { try await client.post("admin/coupons/requests/\(id.pathEncoded)/reject") }
    func deleteRequest(_ id: String) async throws -> ActionResponse { try await client.delete("admin/coupons/requests/\(id.pathEncoded)") }
    func waiverFinance(page: Int, q: String?, filters: [String: String]) async throws -> WaiverFinanceResponse {
        try await client.get("admin/coupons/finance", query: merged(["page": "\(page)", "q": q], filters))
    }
}
