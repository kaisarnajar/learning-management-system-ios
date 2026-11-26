import Foundation

/// /api/v1 (Android's AcademyApi). Every call goes through [apiCall] in the repositories for error handling.
struct AcademyAPI: Sendable {
    let client: APIClient

    // MARK: auth & account
    func login(_ body: LoginRequest) async throws -> TokenResponse { try await client.post("auth/login", body) }
    func register(_ body: RegisterRequest) async throws -> TokenResponse { try await client.post("auth/register", body) }
    func google(_ body: GoogleRequest) async throws -> TokenResponse { try await client.post("auth/google", body) }
    func logout(_ body: RefreshRequest) async throws -> OkResponse { try await client.post("auth/logout", body) }
    func forgotPassword(_ body: EmailRequest) async throws -> OkResponse { try await client.post("auth/forgot-password", body) }
    func resendVerification(_ body: EmailRequest) async throws -> OkResponse { try await client.post("auth/resend-verification", body) }
    func me() async throws -> ProfileResponse { try await client.get("auth/me") }
    func updateProfile(_ body: ProfileUpdate) async throws -> ProfileResponse { try await client.put("auth/me", body) }
    func deleteAccount(_ body: DeleteAccountRequest) async throws -> OkResponse { try await client.delete("auth/me", body) }
    func uploadPhoto(_ image: FilePart) async throws -> PhotoResponse { try await client.multipart("auth/me/photo", fields: [], files: [image]) }
    func removePhoto() async throws -> PhotoResponse { try await client.delete("auth/me/photo") }
    func changePassword(_ body: ChangePasswordRequest) async throws -> OkResponse { try await client.post("auth/change-password", body) }

    // MARK: public content
    func appConfig() async throws -> AppConfig { try await client.get("app-config") }
    func home() async throws -> HomeResponse { try await client.get("home") }
    func courses(page: Int, search: String?, category: String? = nil) async throws -> Paged<Course> {
        try await client.get("courses", query: ["page": "\(page)", "search": search, "category": category])
    }
    func course(_ id: String) async throws -> CourseDetailResponse { try await client.get("courses/\(id.pathEncoded)") }
    func teachers(page: Int, search: String?) async throws -> Paged<Teacher> { try await client.get("teachers", query: ["page": "\(page)", "search": search]) }
    func teacher(_ id: String) async throws -> TeacherDetailResponse { try await client.get("teachers/\(id.pathEncoded)") }
    func blog(page: Int, search: String?) async throws -> Paged<BlogPost> { try await client.get("blog", query: ["page": "\(page)", "search": search]) }
    func blogPost(_ id: String) async throws -> BlogPostResponse { try await client.get("blog/\(id.pathEncoded)") }
    func blogComments(_ id: String, skip: Int) async throws -> CommentsPage { try await client.get("blog/\(id.pathEncoded)/comments", query: ["skip": "\(skip)"]) }
    func addComment(_ id: String, _ body: ContentRequest) async throws -> CommentResponse { try await client.post("blog/\(id.pathEncoded)/comments", body) }
    func toggleLike(_ id: String) async throws -> LikeResponse { try await client.post("blog/\(id.pathEncoded)/like") }
    func deleteComment(_ id: String) async throws -> OkResponse { try await client.delete("blog/comments/\(id.pathEncoded)") }
    func fatwas(page: Int, search: String?, category: String?) async throws -> Paged<Fatwa> {
        try await client.get("fatwa", query: ["page": "\(page)", "search": search, "category": category])
    }
    func fatwa(_ id: String) async throws -> FatwaResponse { try await client.get("fatwa/\(id.pathEncoded)") }
    func askFatwa(_ body: AskFatwaRequest) async throws -> OkResponse { try await client.post("fatwa", body) }
    func library(page: Int, search: String?, topic: String? = nil) async throws -> Paged<LibraryItem> {
        try await client.get("library", query: ["page": "\(page)", "search": search, "topic": topic])
    }
    func libraryItem(_ id: String) async throws -> LibraryItemResponse { try await client.get("library/\(id.pathEncoded)") }
    func books(page: Int, search: String?) async throws -> Paged<Book> { try await client.get("bookstore", query: ["page": "\(page)", "search": search]) }
    func book(_ id: String) async throws -> BookResponse { try await client.get("bookstore/\(id.pathEncoded)") }
    func announcements(page: Int, search: String?) async throws -> Paged<SiteAnnouncement> {
        try await client.get("announcements", query: ["page": "\(page)", "search": search])
    }
    func announcement(_ id: String) async throws -> AnnouncementResponse { try await client.get("announcements/\(id.pathEncoded)") }
    func paymentSettings() async throws -> PaymentSettingsResponse { try await client.get("payment-settings") }
    func contact(_ body: ContactRequest) async throws -> OkResponse { try await client.post("contact", body) }

    // MARK: student
    func enrollments() async throws -> EnrollmentsResponse { try await client.get("enrollments") }
    func enroll(_ body: EnrollRequest) async throws -> EnrollResponse { try await client.post("enrollments", body) }
    func courseAnnouncements(_ courseId: String, pageSize: Int = 50) async throws -> CourseAnnouncementsResponse {
        try await client.get("courses/\(courseId.pathEncoded)/announcements", query: ["pageSize": "\(pageSize)"])
    }
    func attendance(courseId: String?) async throws -> AttendanceResponse { try await client.get("student/attendance", query: ["courseId": courseId]) }
    func grades(courseId: String?) async throws -> GradesResponse { try await client.get("student/grades", query: ["courseId": courseId]) }
    func paymentQuote(courseId: String, type: String) async throws -> PaymentQuote {
        try await client.get("payments/quote", query: ["courseId": courseId, "type": type])
    }
    func submitPayment(fields: [(String, String)], screenshot: FilePart?) async throws -> OkResponse {
        try await client.multipart("payments/submit", fields: fields, files: screenshot.map { [$0] } ?? [])
    }
    func paymentHistory() async throws -> PaymentHistory { try await client.get("payments/history") }
    func waiverRequests() async throws -> WaiverRequestsResponse { try await client.get("waiver-requests") }
    func requestWaiver(_ body: WaiverRequestBody) async throws -> OkResponse { try await client.post("waiver-requests", body) }
    func coursePage(page: Int, pageSize: Int) async throws -> Paged<Course> {
        try await client.get("courses", query: ["page": "\(page)", "pageSize": "\(pageSize)"])
    }
    func myReviews() async throws -> ReviewsResponse { try await client.get("reviews") }
    func addReview(_ body: ReviewRequest) async throws -> OkResponse { try await client.post("reviews", body) }

    // MARK: bookstore
    func cart() async throws -> CartResponse { try await client.get("bookstore/cart") }
    func setCartLine(_ body: CartLine) async throws -> CartResponse { try await client.patch("bookstore/cart", body) }
    func checkoutQuote(_ body: CartReplace) async throws -> CheckoutQuote { try await client.post("bookstore/checkout-quote", body) }
    func placeOrder(fields: [(String, String)], screenshot: FilePart?) async throws -> OkResponse {
        try await client.multipart("bookstore/orders", fields: fields, files: screenshot.map { [$0] } ?? [])
    }
    func orders() async throws -> OrdersResponse { try await client.get("bookstore/orders") }
    func order(_ id: String) async throws -> OrderResponse { try await client.get("bookstore/orders/\(id.pathEncoded)") }

    // MARK: notifications
    func notifications(page: Int, filter: String = "all") async throws -> Paged<AppNotification> {
        try await client.get("notifications", query: ["page": "\(page)", "filter": filter])
    }
    func notification(_ id: String) async throws -> NotificationResponse { try await client.get("notifications/\(id.pathEncoded)") }
    func markRead(_ body: MarkReadRequest) async throws -> OkResponse { try await client.patch("notifications", body) }
}

extension String {
    /// The value as one URL path segment (an id with "/" or spaces can't break out of its place).
    var pathEncoded: String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }

    /// nil for a blank string (Kotlin's ifBlank { null }).
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }

    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
