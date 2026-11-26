import SwiftUI

/*
 * The staff screens (teacher, admin and developer), opened as `Route.manage(...)`: one case per screen of every
 * section, from Android's ManageGraph.kt and the section graphs (StudentsAdmin.kt, TeachHome.kt / TeachRoutes.kt,
 * BookstoreGraph.kt, PeopleGraph.kt, CoursesGraph.kt, ContentGraph.kt, MoneyGraph.kt).
 *
 * Android hands each screen callbacks; here a screen pushes the next route itself. The comment on each case says
 * where Android's callbacks lead ("→"), so a section port keeps the same navigation. "replaces" means Android pops
 * the current screen first (`popUpTo … inclusive`): use `nav.replace(upTo: .manage(current), with: .manage(next))`.
 */
enum ManageRoute: Hashable, Sendable {
    // MARK: students (StudentsAdmin.kt)
    /// StudentsListScreen. open → .studentAdmin
    case studentsAdmin
    /// StudentDetailScreen. edit → .studentEdit
    case studentAdmin(id: String)
    /// StudentEditScreen.
    case studentEdit(id: String)

    // MARK: teach (TeachHome.kt, TeachRoutes.kt)
    /// TeacherStudentsScreen. open → .teacherStudent
    case teacherStudents(courseId: String)
    /// TeacherStudentScreen. attendance → .studentAttendance(.teacher), grades → .studentGrades(.teacher),
    /// message → .courseAnnouncements(.teacher, enrollmentId, studentName)
    case teacherStudent(courseId: String, enrollmentId: String)
    /// ManageFatwaListScreen(audience: .teacher). open → .teacherFatwaDetail
    case teacherFatwa
    /// TeacherBlogsListScreen. edit → .teacherBlogForm(id), new → .teacherBlogForm()
    case teacherBlogs

    // MARK: bookstore (BookstoreGraph.kt)
    /// BooksListScreen. open → .bookAdmin, add → .bookNew, orders → .bookOrdersAdmin
    case booksAdmin
    /// BookDetailScreen. edit → .bookEdit
    case bookAdmin(id: String)
    /// BookFormScreen(id: nil).
    case bookNew
    /// BookFormScreen(id:).
    case bookEdit(id: String)
    /// BookOrdersListScreen. open → .bookOrderAdmin, books → .booksAdmin (Android: launchSingleTop)
    case bookOrdersAdmin
    /// BookOrderDetailScreen.
    case bookOrderAdmin(id: String)

    // MARK: people (PeopleGraph.kt)
    /// TeachersListScreen. open → .teacherAdmin, add → .teacherForm()
    case teachersAdmin
    /// TeacherDetailScreen. edit → .teacherForm(id)
    case teacherAdmin(id: String)
    /// TeacherFormScreen; nil id adds a teacher.
    case teacherForm(id: String? = nil)
    /// EnrollmentsScreen. student → .studentAdmin, enroll → .enrollStudent, payments → routeForAdminHref("/admin/payments")
    case enrollmentsAdmin
    /// EnrollStudentScreen.
    case enrollStudent
    /// CertificatesListScreen. open → .certificateAdmin, generate → .generateCertificate
    case certificatesAdmin
    /// CertificateDetailScreen.
    case certificateAdmin(enrollmentId: String)
    /// GenerateCertificateScreen. generated(id) → .certificateAdmin(id), replaces this screen
    case generateCertificate
    /// ReviewsListScreen. open → .reviewAdmin, edit → .reviewEdit
    case reviewsAdmin
    /// ReviewDetailScreen. edit → .reviewEdit
    case reviewAdmin(id: String)
    /// ReviewEditScreen.
    case reviewEdit(id: String)
    /// InquiriesListScreen. open → .inquiryAdmin, reply → .inquiryReply
    case inquiriesAdmin
    /// InquiryDetailScreen. reply → .inquiryReply
    case inquiryAdmin(id: String)
    /// InquiryReplyScreen.
    case inquiryReply(id: String)
    /// AuditLogScreen.
    case auditLog

    // MARK: courses (CoursesGraph.kt; shared routes carry the portal)
    /// CoursesAdminListScreen. open → .courseHub(.admin), add → .courseForm()
    case coursesAdmin
    /// CourseFormScreen; nil id adds a course.
    case courseForm(id: String? = nil)
    /// CourseRosterScreen. attendance(e) → .studentAttendance(.admin), grades(e) → .studentGrades(.admin)
    case courseRoster(courseId: String)
    /// CourseHubScreen. students → .courseRoster (admin) / .teacherStudents (teacher), attendance → .attendanceList,
    /// grades → .gradeList, announcements → .courseAnnouncements, edit → .courseForm(id)
    case courseHub(portal: Portal, courseId: String)
    /// CourseAnnouncementsScreen (a student's messages when enrollmentId is set). new → .announcementForm(…, nil, …),
    /// edit(a) → .announcementForm(…, a, …)
    case courseAnnouncements(portal: Portal, courseId: String, enrollmentId: String? = nil, studentName: String? = nil)
    /// AnnouncementFormScreen.
    case announcementForm(portal: Portal, courseId: String, enrollmentId: String? = nil, announcementId: String? = nil, studentName: String? = nil)
    /// AttendanceListScreen. take → .attendanceTake(date: nil), open(d) → .attendanceDay(d)
    case attendanceList(portal: Portal, courseId: String)
    /// AttendanceTakeScreen. editExisting(d) → .attendanceTake(date: d), replaces this screen
    case attendanceTake(portal: Portal, courseId: String, date: String? = nil)
    /// AttendanceDayScreen. edit → .attendanceTake(date), student(e) → .studentAttendance
    case attendanceDay(portal: Portal, courseId: String, date: String)
    /// StudentAttendanceScreen.
    case studentAttendance(portal: Portal, courseId: String, enrollmentId: String)
    /// GradeListScreen. add → .gradeForm(nil), edit(g) → .gradeForm(g)
    case gradeList(portal: Portal, courseId: String)
    /// GradeFormScreen.
    case gradeForm(portal: Portal, courseId: String, gradeId: String? = nil)
    /// StudentGradesScreen.
    case studentGrades(portal: Portal, courseId: String, enrollmentId: String)

    // MARK: content (ContentGraph.kt)
    /// AnnouncementsListScreen. open → .siteAnnouncementForm(id), new → .siteAnnouncementForm()
    case announcementsAdmin
    /// SiteAnnouncementFormScreen; nil id is a new announcement.
    case siteAnnouncementForm(id: String? = nil)
    /// BlogsListScreen. open → .blogForm(id), new → .blogForm()
    case blogsAdmin
    /// BlogEditorScreen(mode: .admin).
    case blogForm(id: String? = nil)
    /// BlogApprovalsListScreen. open → .blogApproval, edit → .blogForm(id)
    case blogApprovals
    /// BlogApprovalDetailScreen. edit → .blogForm(id)
    case blogApproval(id: String)
    /// BlogEditorScreen(mode: .teacher).
    case teacherBlogForm(id: String? = nil)
    /// ManageFatwaListScreen(audience: .admin). open → .fatwaAdminDetail
    case fatwaAdmin
    /// FatwaAnswerScreen(audience: .admin).
    case fatwaAdminDetail(id: String)
    /// FatwaAnswerScreen(audience: .teacher).
    case teacherFatwaDetail(id: String)
    /// ManageLibraryListScreen. open → .libraryAdminDetail, edit → .libraryForm(id), new → .libraryForm()
    case libraryAdmin
    /// LibraryDetailScreen. edit → .libraryForm(id)
    case libraryAdminDetail(id: String)
    /// LibraryFormScreen.
    case libraryForm(id: String? = nil)
    /// InspirationListScreen. open → .inspirationDetail, edit → .inspirationForm(id), new → .inspirationForm()
    case inspirationAdmin
    /// InspirationDetailScreen. edit → .inspirationForm(id)
    case inspirationDetail(id: String)
    /// InspirationFormScreen.
    case inspirationForm(id: String? = nil)

    // MARK: money (MoneyGraph.kt)
    /// PendingPaymentsScreen. openReceipt(id) → .receipt
    case pendingPayments
    /// CompletedPaymentsScreen. openReceipt(id) → .receipt, openReceipts → .receipts
    case completedPayments
    /// ReceiptsScreen. open → .receipt
    case receipts
    /// ReceiptDetailScreen.
    case receipt(recordId: String)
    /// FinanceScreen. bookstore → .bookstoreFinance (replaces this screen), record(expense) → .transactions(expense:)
    case finance
    /// BookstoreFinanceScreen. courses → .finance (replaces this screen)
    case bookstoreFinance
    /// TransactionsScreen.
    case transactions(expense: Bool = false)
    /// PaymentSettingsScreen.
    case paymentSettings
    /// ShippingChargesScreen.
    case shippingCharges
    /// CouponsScreen. edit(route) → .couponForm(route), finance → .waiverFinance
    case coupons
    /// WaiverFinanceScreen. openReceipt(id) → .receipt
    case waiverFinance
    /// CouponFormScreen.
    case couponForm(CouponFormRoute)
}

/// The coupon form's arguments; an edit carries the coupon's current values (there is no single-coupon read).
struct CouponFormRoute: Hashable, Sendable {
    var id: String? = nil
    var type: String = "DEFAULT"
    var code: String = ""
    var percentage: String = ""
    var validFrom: String = ""
    var validUntil: String = ""
    var courseId: String = ""
    var gender: String = ""
    var applyTo: String = "BOTH"
    var isActive: Bool = true
}

// MARK: - website links

/// Website admin page → the app screen that does the same job (Android's adminHrefRoutes).
let adminHrefRoutes: [String: ManageRoute] = [
    "/admin/students": .studentsAdmin,
    "/admin/bookstore": .booksAdmin,
    "/admin/bookstore/orders": .bookOrdersAdmin,
    "/admin/teachers": .teachersAdmin,
    "/admin/enrollments": .enrollmentsAdmin,
    "/admin/certificates": .certificatesAdmin,
    "/admin/review-approvals": .reviewsAdmin,
    "/admin/contact-inquiries": .inquiriesAdmin,
    "/admin/audit-log": .auditLog,
    "/admin/courses": .coursesAdmin,
    "/admin/announcements": .announcementsAdmin,
    "/admin/blogs": .blogsAdmin,
    "/admin/blog-approvals": .blogApprovals,
    "/admin/fatwa": .fatwaAdmin,
    "/admin/library": .libraryAdmin,
    "/admin/daily-inspiration": .inspirationAdmin,
    "/admin/payments": .pendingPayments,
    "/admin/completed-payments": .completedPayments,
    "/admin/receipts": .receipts,
    "/admin/finance": .finance,
    "/admin/finance/bookstore": .bookstoreFinance,
    "/admin/transactions": .transactions(),
    "/admin/payment-settings": .paymentSettings,
    "/admin/shipping-charges": .shippingCharges,
    "/admin/coupons": .coupons,
    "/admin/coupons/finance": .waiverFinance,
]

/// A record's own page on the website (`/admin/students/{id}`, …) → its app screen.
private let adminRecordPages: [String: @Sendable (String) -> ManageRoute] = [
    "students": { .studentAdmin(id: $0) },
    "teachers": { .teacherAdmin(id: $0) },
    "bookstore": { .bookAdmin(id: $0) },
    "certificates": { .certificateAdmin(enrollmentId: $0) },
    "contact-inquiries": { .inquiryAdmin(id: $0) },
    "review-approvals": { .reviewAdmin(id: $0) },
    "blog-approvals": { .blogApproval(id: $0) },
    "fatwa": { .fatwaAdminDetail(id: $0) },
    "library": { .libraryAdminDetail(id: $0) },
    "daily-inspiration": { .inspirationDetail(id: $0) },
    "receipts": { .receipt(recordId: $0) },
    "courses": { .courseHub(portal: .admin, courseId: $0) },
]

/// A course's admin pages (`/admin/courses/{id}/grades`, …) → their app screens.
private let adminCoursePages: [String: @Sendable (String) -> ManageRoute] = [
    "students": { .courseRoster(courseId: $0) },
    "attendance": { .attendanceList(portal: .admin, courseId: $0) },
    "grades": { .gradeList(portal: .admin, courseId: $0) },
    "announcements": { .courseAnnouncements(portal: .admin, courseId: $0) },
]

/// The app screen for a website admin path (a section, or one record's page), or nil when the app has none.
func routeForAdminHref(_ href: String) -> ManageRoute? {
    var path = href.components(separatedBy: "#")[0].components(separatedBy: "?")[0]
    while path.hasSuffix("/") { path.removeLast() }
    if let route = adminHrefRoutes[path] { return route }
    let rest = path.hasPrefix("/admin/") ? String(path.dropFirst("/admin/".count)) : path
    return adminRecordRoute(rest.components(separatedBy: "/"))
}

/// `section/{id}/page` or `section/sub/{id}`.
private let recordUnderSection = 3

/// One record's page ([p] is the path after /admin/, split): its screen, or nil (forms such as `/edit` have none).
private func adminRecordRoute(_ p: [String]) -> ManageRoute? {
    guard p.count > 1, !p[1].trimmed.isEmpty, p[1] != "new" else { return nil }
    let id = p[1]
    if p.count == 2 { return adminRecordPages[p[0]]?(id) }
    if p[0] == "bookstore", p[1] == "orders", p.count == recordUnderSection { return .bookOrderAdmin(id: p[2]) }
    if p[0] == "courses", p.count == recordUnderSection { return adminCoursePages[p[2]]?(id) }
    return nil
}

// MARK: - registry

/// The screen for a staff route (Android's manageGraph: each section's composables).
struct ManageDestination: View {
    let route: ManageRoute

    var body: some View {
        switch route {
        // students
        case .studentsAdmin: StudentsListScreen()
        case .studentAdmin(let id): StudentDetailScreen(id: id)
        case .studentEdit(let id): StudentEditScreen(id: id)
        // teach
        case .teacherStudents(let courseId): TeacherStudentsScreen(courseId: courseId)
        case .teacherStudent(let courseId, let enrollmentId): TeacherStudentScreen(courseId: courseId, enrollmentId: enrollmentId)
        case .teacherFatwa: ManageFatwaListScreen(audience: .teacher)
        case .teacherBlogs: TeacherBlogsListScreen()
        // bookstore
        case .booksAdmin: BooksListScreen()
        case .bookAdmin(let id): BookDetailScreen(id: id)
        case .bookNew: BookFormScreen(id: nil)
        case .bookEdit(let id): BookFormScreen(id: id)
        case .bookOrdersAdmin: BookOrdersListScreen()
        case .bookOrderAdmin(let id): BookOrderDetailScreen(id: id)
        // people
        case .teachersAdmin: TeachersListScreen()
        case .teacherAdmin(let id): TeacherDetailScreen(id: id)
        case .teacherForm(let id): TeacherFormScreen(id: id)
        case .enrollmentsAdmin: EnrollmentsScreen()
        case .enrollStudent: EnrollStudentScreen()
        case .certificatesAdmin: CertificatesListScreen()
        case .certificateAdmin(let enrollmentId): CertificateDetailScreen(enrollmentId: enrollmentId)
        case .generateCertificate: GenerateCertificateScreen()
        case .reviewsAdmin: ReviewsListScreen()
        case .reviewAdmin(let id): ReviewDetailScreen(id: id)
        case .reviewEdit(let id): ReviewEditScreen(id: id)
        case .inquiriesAdmin: InquiriesListScreen()
        case .inquiryAdmin(let id): InquiryDetailScreen(id: id)
        case .inquiryReply(let id): InquiryReplyScreen(id: id)
        case .auditLog: AuditLogScreen()
        // courses
        case .coursesAdmin: CoursesAdminListScreen()
        case .courseForm(let id): CourseFormScreen(id: id)
        case .courseRoster(let courseId): CourseRosterScreen(courseId: courseId)
        case .courseHub(let portal, let courseId): CourseHubScreen(portal: portal, courseId: courseId)
        case .courseAnnouncements(let portal, let courseId, let enrollmentId, let studentName):
            CourseAnnouncementsScreen(portal: portal, courseId: courseId, enrollmentId: enrollmentId, studentName: studentName)
        case .announcementForm(let portal, let courseId, let enrollmentId, let announcementId, let studentName):
            AnnouncementFormScreen(portal: portal, courseId: courseId, enrollmentId: enrollmentId, announcementId: announcementId, studentName: studentName)
        case .attendanceList(let portal, let courseId): AttendanceListScreen(portal: portal, courseId: courseId)
        case .attendanceTake(let portal, let courseId, let date): AttendanceTakeScreen(portal: portal, courseId: courseId, date: date)
        case .attendanceDay(let portal, let courseId, let date): AttendanceDayScreen(portal: portal, courseId: courseId, date: date)
        case .studentAttendance(let portal, let courseId, let enrollmentId):
            StudentAttendanceScreen(portal: portal, courseId: courseId, enrollmentId: enrollmentId)
        case .gradeList(let portal, let courseId): GradeListScreen(portal: portal, courseId: courseId)
        case .gradeForm(let portal, let courseId, let gradeId): GradeFormScreen(portal: portal, courseId: courseId, gradeId: gradeId)
        case .studentGrades(let portal, let courseId, let enrollmentId):
            StudentGradesScreen(portal: portal, courseId: courseId, enrollmentId: enrollmentId)
        // content
        case .announcementsAdmin: AnnouncementsListScreen()
        case .siteAnnouncementForm(let id): SiteAnnouncementFormScreen(id: id)
        case .blogsAdmin: BlogsListScreen()
        case .blogForm(let id): BlogEditorScreen(mode: .admin, id: id)
        case .blogApprovals: BlogApprovalsListScreen()
        case .blogApproval(let id): BlogApprovalDetailScreen(id: id)
        case .teacherBlogForm(let id): BlogEditorScreen(mode: .teacher, id: id)
        case .fatwaAdmin: ManageFatwaListScreen(audience: .admin)
        case .fatwaAdminDetail(let id): FatwaAnswerScreen(audience: .admin, id: id)
        case .teacherFatwaDetail(let id): FatwaAnswerScreen(audience: .teacher, id: id)
        case .libraryAdmin: ManageLibraryListScreen()
        case .libraryAdminDetail(let id): LibraryDetailScreen(id: id)
        case .libraryForm(let id): LibraryFormScreen(id: id)
        case .inspirationAdmin: InspirationListScreen()
        case .inspirationDetail(let id): InspirationDetailScreen(id: id)
        case .inspirationForm(let id): InspirationFormScreen(id: id)
        // money
        case .pendingPayments: PendingPaymentsScreen()
        case .completedPayments: CompletedPaymentsScreen()
        case .receipts: ReceiptsScreen()
        case .receipt(let recordId): ReceiptDetailScreen(recordId: recordId)
        case .finance: FinanceScreen()
        case .bookstoreFinance: BookstoreFinanceScreen()
        case .transactions(let expense): TransactionsScreen(expense: expense)
        case .paymentSettings: PaymentSettingsScreen()
        case .shippingCharges: ShippingChargesScreen()
        case .coupons: CouponsScreen()
        case .waiverFinance: WaiverFinanceScreen()
        case .couponForm(let route): CouponFormScreen(route: route)
        }
    }
}
