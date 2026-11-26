import Foundation

// The bookstore admin (/api/v1/admin/bookstore), ported from Android's data/staff/bookstore/BookstoreApi.kt.

struct AdminBook: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var title: String = ""
    @Default<Empty.Text> var author: String = ""
    @Default<Empty.Text> var description: String = ""
    @Default<Zero> var priceInrPaise: Int = 0
    @Default<Zero> var mrpInrPaise: Int = 0
    @Default<Zero> var purchasePriceInrPaise: Int = 0
    @Default<Zero> var inventoryPurchased: Int = 0
    @Default<Zero> var weightInGrams: Int = 0
    @Default<Available> var status: String = "AVAILABLE"
    @Default<Empty.Text> var statusLabel: String = ""
    var imagePath: String? = nil
    @Default<False> var published: Bool = false
    @Default<False> var featuredOnHomepage: Bool = false
    /// Featured and published: what the website's "Homepage" column calls "Featured".
    @Default<False> var featured: Bool = false
    var createdAt: String? = nil
    var updatedAt: String? = nil
}

struct BookStatusOption: Model { var value: String; var label: String }

struct BookStock: Model {
    @Default<Zero> var purchased: Int = 0
    @Default<Zero> var adjustments: Int = 0
    @Default<Zero> var committed: Int = 0
    @Default<Zero> var available: Int = 0
}

struct AdminBookResponse: Model {
    var book: AdminBook
    var stock: BookStock? = nil
    @Default<Empty.List<BookStatusOption>> var statusOptions: [BookStatusOption] = []
    @Default<Zero> var featuredCount: Int = 0
    @Default<Four> var featuredMax: Int = 4
}

struct BookFormOptions: Model {
    @Default<Empty.List<BookStatusOption>> var statusOptions: [BookStatusOption] = []
    @Default<Zero> var featuredCount: Int = 0
    @Default<Four> var featuredMax: Int = 4
}

struct BookOrderLine: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var bookId: String = ""
    @Default<Empty.Text> var title: String = ""
    @Default<Empty.Text> var author: String = ""
    var imagePath: String? = nil
    @Default<One> var quantity: Int = 1
    @Default<Zero> var priceAtPurchaseInrPaise: Int = 0
    @Default<Zero> var lineTotalInrPaise: Int = 0
}

struct BookOrderRow: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var shortId: String = ""
    @Default<Empty.Text> var status: String = ""
    @Default<Empty.Text> var statusLabel: String = ""
    var customerName: String? = nil
    @Default<Empty.Text> var customerEmail: String = ""
    @Default<Zero> var totalAmountInrPaise: Int = 0
    @Default<Zero> var shippingChargeInrPaise: Int = 0
    var paymentMethod: String? = nil
    var upiTransactionId: String? = nil
    var paymentScreenshotPath: String? = nil
    var deliveryAddress: String? = nil
    var deliveryPinCode: String? = nil
    var deliveryPhoneNumber: String? = nil
    var notes: String? = nil
    var courierServiceName: String? = nil
    var trackingId: String? = nil
    var createdAt: String? = nil
    @Default<Empty.List<BookOrderLine>> var items: [BookOrderLine] = []
}

struct BookOrderCounts: Model, Initable {
    @Default<Zero> var pending: Int = 0
    @Default<Zero> var approved: Int = 0
    @Default<Zero> var completed: Int = 0
}

/// A page of book orders, with the status tab counts.
struct BookOrdersPage: Model {
    @Default<Empty.List<BookOrderRow>> var data: [BookOrderRow] = []
    @Default<Zero> var totalCount: Int = 0
    @Default<One> var page: Int = 1
    @Default<Ten> var pageSize: Int = 10
    @Default<PendingLower> var status: String = "pending"
    @Default<Fallback<BookOrderCounts>> var counts: BookOrderCounts = BookOrderCounts()

    /// The rows as the app's `Paged` list.
    func paged() -> Paged<BookOrderRow> { Paged(data: data, totalCount: totalCount, page: page, pageSize: pageSize) }
}

struct BookOrderCustomer: Model, Initable {
    @Default<Empty.Text> var id: String = ""
    var name: String? = nil
    @Default<Empty.Text> var email: String = ""
}

struct BookOrderDetail: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var shortId: String = ""
    @Default<Empty.Text> var status: String = ""
    @Default<Empty.Text> var statusLabel: String = ""
    @Default<False> var deleted: Bool = false
    var createdAt: String? = nil
    @Default<Fallback<BookOrderCustomer>> var customer: BookOrderCustomer = BookOrderCustomer()
    var deliveryAddress: String? = nil
    var deliveryPinCode: String? = nil
    var deliveryPhoneNumber: String? = nil
    var notes: String? = nil
    var paymentMethod: String? = nil
    var upiTransactionId: String? = nil
    var paymentScreenshotPath: String? = nil
    var courierServiceName: String? = nil
    var trackingId: String? = nil
    @Default<Empty.List<BookOrderLine>> var items: [BookOrderLine] = []
    @Default<Zero> var subtotalInrPaise: Int = 0
    @Default<Zero> var shippingChargeInrPaise: Int = 0
    @Default<Zero> var totalAmountInrPaise: Int = 0
}

struct BookOrderEvent: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var action: String = ""
    @Default<Empty.Text> var label: String = ""
    var actorEmail: String? = nil
    var reason: String? = nil
    var createdAt: String? = nil
}

struct BookOrderResponse: Model {
    var order: BookOrderDetail
    @Default<Empty.List<BookOrderEvent>> var timeline: [BookOrderEvent] = []
}

struct BookstoreAdminAPI: StaffService {
    let client: APIClient

    func books(page: Int, q: String?) async throws -> Paged<AdminBook> {
        try await client.get("admin/bookstore", query: ["page": "\(page)", "q": q])
    }

    func formOptions() async throws -> BookFormOptions { try await client.get("admin/bookstore/new") }

    func book(_ id: String) async throws -> AdminBookResponse { try await client.get("admin/bookstore/\(id.pathEncoded)") }

    func create(_ form: FormBody) async throws -> ActionResponse { try await client.form("POST", "admin/bookstore", form) }

    func update(_ id: String, _ form: FormBody) async throws -> ActionResponse {
        try await client.form("PATCH", "admin/bookstore/\(id.pathEncoded)", form)
    }

    func delete(_ id: String) async throws -> ActionResponse { try await client.delete("admin/bookstore/\(id.pathEncoded)") }

    func orders(page: Int, q: String?, status: String?, pageSize: Int? = nil) async throws -> BookOrdersPage {
        try await client.get("admin/bookstore/orders", query: ["page": "\(page)", "q": q, "status": status, "pageSize": pageSize.map { "\($0)" }])
    }

    func order(_ id: String) async throws -> BookOrderResponse { try await client.get("admin/bookstore/orders/\(id.pathEncoded)") }

    /// approve, decline, ship (courierServiceName, trackingId), refund, void (reason).
    func orderAction(_ id: String, action: String, _ form: FormBody) async throws -> ActionResponse {
        try await client.form("POST", "admin/bookstore/orders/\(id.pathEncoded)/\(action.pathEncoded)", form)
    }
}
