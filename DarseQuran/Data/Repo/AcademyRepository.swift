import Foundation
import os

/// The last home screen the server sent, kept on disk so that a cold start shows it at once while the new one loads.
/// It is the public /home answer, the same for every visitor, so it is not cleared when someone signs out.
struct SavedHome: Sendable {
    let file: URL

    /// The saved home screen, or nil when there is none or it no longer reads (e.g. written by an older app).
    func read() -> HomeResponse? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(HomeResponse.self, from: data)
    }

    /// Replaces the saved copy atomically, so a crash mid-write can't leave half a file.
    func write(_ home: HomeResponse) {
        guard let data = try? JSONEncoder().encode(home) else { return }
        try? data.write(to: file, options: .atomic)
    }
}

/// Everything the app reads and writes apart from sign-in (Android's AcademyRepository). Thin: errors become ApiError.
final class AcademyRepository: Sendable {
    let api: AcademyAPI
    /// The file that keeps the home screen between runs, one per server.
    private let savedHome: (@Sendable (AppEnvironment) -> SavedHome)?
    private let state = OSAllocatedUnfairLock<(config: AppConfig?, home: HomeResponse?)>(initialState: (nil, nil))
    private let configGate = AsyncGate()

    init(api: AcademyAPI, savedHome: (@Sendable (AppEnvironment) -> SavedHome)? = nil) {
        self.api = api
        self.savedHome = savedHome
    }

    /// Branding, lookups and feature switches; fetched once per process.
    func appConfig(force: Bool = false) async -> ApiResult<AppConfig> {
        await configGate.run {
            if let cached = self.state.withLock({ $0.config }), !force { return .success(cached) }
            let result = await apiCall { try await self.api.appConfig() }
            if case .success(let c) = result { self.state.withLock { $0.config = c } }
            return result
        }
    }

    /// The config already loaded, if any.
    var cachedConfig: AppConfig? { state.withLock { $0.config } }
    func cachedHome() -> HomeResponse? { state.withLock { $0.home } }

    /// Forgets what was cached from the previous environment.
    func clearCaches() { state.withLock { $0 = (nil, nil) } }

    func home() async -> ApiResult<HomeResponse> {
        // An answer that arrives after a server switch belongs to the old server: don't keep it for the new one.
        let env = CurrentEnvironment.value
        let result = await apiCall { try await api.home() }
        if case .success(let home) = result, env == CurrentEnvironment.value {
            state.withLock { $0.home = home }
            savedHome?(env).write(home)
        }
        return result
    }

    /// The home screen to show while [home] loads: this run's, else the one saved by the last run on this server.
    func lastHome() -> HomeResponse? { cachedHome() ?? savedHome?(CurrentEnvironment.value).read() }

    // MARK: catalogue & content
    func courses(page: Int, search: String?, category: String? = nil) async -> ApiResult<Paged<Course>> {
        await apiCall { try await api.courses(page: page, search: search?.nilIfBlank, category: category) }
    }
    func course(_ id: String) async -> ApiResult<CourseDetailResponse> { await apiCall { try await api.course(id) } }
    func teachers(page: Int, search: String?) async -> ApiResult<Paged<Teacher>> { await apiCall { try await api.teachers(page: page, search: search?.nilIfBlank) } }
    func teacher(_ id: String) async -> ApiResult<TeacherDetailResponse> { await apiCall { try await api.teacher(id) } }
    func blog(page: Int, search: String?) async -> ApiResult<Paged<BlogPost>> { await apiCall { try await api.blog(page: page, search: search?.nilIfBlank) } }
    func blogPost(_ id: String) async -> ApiResult<BlogPost> { await apiCall { try await api.blogPost(id).post } }
    func blogComments(_ id: String, skip: Int) async -> ApiResult<[Comment]> { await apiCall { try await api.blogComments(id, skip: skip).data } }
    func addComment(_ id: String, content: String) async -> ApiResult<Comment> { await apiCall { try await api.addComment(id, ContentRequest(content: content)).comment } }
    func deleteComment(_ id: String) async -> ApiResult<OkResponse> { await apiCall { try await api.deleteComment(id) } }
    func toggleLike(_ id: String) async -> ApiResult<LikeResponse> { await apiCall { try await api.toggleLike(id) } }
    func fatwas(page: Int, search: String?, category: String?) async -> ApiResult<Paged<Fatwa>> {
        await apiCall { try await api.fatwas(page: page, search: search?.nilIfBlank, category: category) }
    }
    func fatwa(_ id: String) async -> ApiResult<Fatwa> { await apiCall { try await api.fatwa(id).fatwa } }
    func askFatwa(_ body: AskFatwaRequest) async -> ApiResult<OkResponse> { await apiCall { try await api.askFatwa(body) } }
    func library(page: Int, search: String?, topic: String? = nil) async -> ApiResult<Paged<LibraryItem>> {
        await apiCall { try await api.library(page: page, search: search?.nilIfBlank, topic: topic) }
    }
    func libraryItem(_ id: String) async -> ApiResult<LibraryItem> { await apiCall { try await api.libraryItem(id).item } }
    func books(page: Int, search: String?) async -> ApiResult<Paged<Book>> { await apiCall { try await api.books(page: page, search: search?.nilIfBlank) } }
    func book(_ id: String) async -> ApiResult<Book> { await apiCall { try await api.book(id).book } }
    func announcements(page: Int, search: String?) async -> ApiResult<Paged<SiteAnnouncement>> {
        await apiCall { try await api.announcements(page: page, search: search?.nilIfBlank) }
    }
    func announcement(_ id: String) async -> ApiResult<SiteAnnouncement> { await apiCall { try await api.announcement(id).announcement } }
    func contact(_ body: ContactRequest) async -> ApiResult<OkResponse> { await apiCall { try await api.contact(body) } }

    /// Not cached: the academy can change its UPI or bank details at any time.
    func paymentSettings() async -> ApiResult<PaymentSettings> { await apiCall { try await api.paymentSettings().settings } }

    // MARK: student
    func enrollments() async -> ApiResult<[Enrollment]> { await apiCall { try await api.enrollments().data } }
    func enroll(_ courseId: String) async -> ApiResult<EnrollResponse> { await apiCall { try await api.enroll(EnrollRequest(courseId: courseId)) } }
    func courseAnnouncements(_ courseId: String) async -> ApiResult<CourseAnnouncementsResponse> { await apiCall { try await api.courseAnnouncements(courseId) } }
    func attendance(_ courseId: String) async -> ApiResult<CourseAttendance?> { await apiCall { try await api.attendance(courseId: courseId).attendance.first } }
    func grades(_ courseId: String) async -> ApiResult<CourseGrades?> { await apiCall { try await api.grades(courseId: courseId).grades.first } }
    func paymentQuote(courseId: String, type: String) async -> ApiResult<PaymentQuote> { await apiCall { try await api.paymentQuote(courseId: courseId, type: type) } }
    func paymentHistory() async -> ApiResult<PaymentHistory> { await apiCall { try await api.paymentHistory() } }
    func waiverRequests() async -> ApiResult<[WaiverRequest]> { await apiCall { try await api.waiverRequests().data } }
    func requestWaiver(_ body: WaiverRequestBody) async -> ApiResult<OkResponse> { await apiCall { try await api.requestWaiver(body) } }

    /// Every listed course (all pages), for pickers that need the whole catalogue.
    func allCourses() async -> ApiResult<[Course]> {
        await apiCall {
            var all: [Course] = []
            var page = 1
            var batch: Paged<Course>
            repeat {
                batch = try await api.coursePage(page: page, pageSize: 50) // the server's largest page size
                all += batch.data
                page += 1
            } while !batch.data.isEmpty && all.count < batch.totalCount && page <= 20
            return all
        }
    }
    func myReviews() async -> ApiResult<[Review]> { await apiCall { try await api.myReviews().data } }
    func addReview(_ body: ReviewRequest) async -> ApiResult<OkResponse> { await apiCall { try await api.addReview(body) } }

    /// Submits a fee payment: the form fields of /payments/submit; the screenshot is optional.
    func submitPayment(fields: [(String, String)], screenshot: (Data, String)?) async -> ApiResult<OkResponse> {
        await apiCall { try await api.submitPayment(fields: fields, screenshot: screenshot.map { filePart("screenshot", $0.0, $0.1) }) }
    }

    // MARK: bookstore
    func cart() async -> ApiResult<[CartItem]> { await apiCall { try await api.cart().items } }
    func setCartLine(bookId: String, quantity: Int) async -> ApiResult<[CartItem]> {
        await apiCall { try await api.setCartLine(CartLine(bookId: bookId, quantity: quantity)).items }
    }
    func checkoutQuote(_ lines: [CartLine]) async -> ApiResult<CheckoutQuote> { await apiCall { try await api.checkoutQuote(CartReplace(items: lines)) } }
    func placeOrder(fields: [(String, String)], screenshot: (Data, String)?) async -> ApiResult<OkResponse> {
        await apiCall { try await api.placeOrder(fields: fields, screenshot: screenshot.map { filePart("screenshot", $0.0, $0.1) }) }
    }
    func orders() async -> ApiResult<[BookOrder]> { await apiCall { try await api.orders().orders } }
    func order(_ id: String) async -> ApiResult<BookOrder> { await apiCall { try await api.order(id).order } }

    // MARK: notifications
    func notifications(page: Int, unreadOnly: Bool) async -> ApiResult<Paged<AppNotification>> {
        await apiCall { try await api.notifications(page: page, filter: unreadOnly ? "unread" : "all") }
    }
    func notification(_ id: String) async -> ApiResult<AppNotification> { await apiCall { try await api.notification(id).notification } }
    func markAllRead() async -> ApiResult<OkResponse> { await apiCall { try await api.markRead(MarkReadRequest(markAllRead: true)) } }
}

func filePart(_ name: String, _ data: Data, _ mime: String) -> FilePart {
    FilePart(name: name, filename: "\(name).\(mime.hasSuffix("png") ? "png" : "jpg")", mimeType: mime, data: data)
}

/// Runs one async block at a time (Kotlin's Mutex.withLock).
actor AsyncGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(_ block: @Sendable () async -> T) async -> T {
        if busy { await withCheckedContinuation { waiters.append($0) } }
        busy = true
        defer {
            if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
        }
        return await block()
    }
}
