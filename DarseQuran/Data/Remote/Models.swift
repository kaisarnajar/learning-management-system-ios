import Foundation

/*
 * API models for /api/v1 (see docs/openapi.yaml in the web repository), ported from Android's Models.kt.
 * Every field the app does not strictly need is optional or has a default, and unknown fields are ignored, so the
 * server can grow without breaking installed apps.
 */

typealias Model = Codable & Sendable & Hashable

// MARK: - common

struct Paged<T: Model>: Model {
    @Default<Empty.List<T>> var data: [T] = []
    @Default<Zero> var totalCount: Int = 0
    @Default<One> var page: Int = 1
    @Default<Twenty> var pageSize: Int = 20
    var unreadCount: Int? = nil
}

struct OkResponse: Model {
    @Default<True> var success: Bool = true
}

struct ErrorBody: Model {
    var error: String? = nil
    var code: String? = nil
}

// MARK: - auth

struct LoginRequest: Model { var email: String; var password: String }

struct RegisterRequest: Model {
    var name: String?
    var email: String
    var password: String
    var acceptPolicies: Bool = true
}

struct GoogleRequest: Model { var idToken: String }
struct RefreshRequest: Model { var refreshToken: String }
struct EmailRequest: Model { var email: String }

struct TokenResponse: Model {
    var accessToken: String
    var refreshToken: String
    @Default<Hour> var expiresIn: Int = 3600
    var user: SessionUser? = nil
}

struct SessionUser: Model {
    var id: String
    var email: String
    var name: String? = nil
    var image: String? = nil
    @Default<UserRole> var role: String = "USER"
    var registrationNumber: String? = nil
}

struct Profile: Model {
    var id: String
    var email: String
    var name: String? = nil
    var fatherName: String? = nil
    var dateOfBirth: String? = nil
    var occupation: String? = nil
    var address: String? = nil
    var whatsapp: String? = nil
    var whatsappCountry: String? = nil
    var whatsappLocal: String? = nil
    var gender: String? = nil
    var registrationNumber: String? = nil
    var emailVerified: String? = nil
    var image: String? = nil
    @Default<UserRole> var role: String = "USER"
    @Default<False> var profileComplete: Bool = false
    @Default<True> var hasPassword: Bool = true
    var createdAt: String? = nil
}

struct ProfileResponse: Model { var user: Profile }

struct ProfileUpdate: Model {
    var name: String? = nil
    var fatherName: String? = nil
    var dateOfBirth: String? = nil
    var occupation: String? = nil
    var address: String? = nil
    var gender: String? = nil
    var country: String? = nil
    var whatsapp: String? = nil
}

struct ChangePasswordRequest: Model { var currentPassword: String; var newPassword: String }
struct DeleteAccountRequest: Model { var password: String? = nil; var confirm: String? = nil }
struct PhotoResponse: Model { var image: String? = nil }

// MARK: - config

struct AppConfig: Model, Initable {
    @Default<Fallback<BrandInfo>> var brand: BrandInfo = BrandInfo()
    @Default<Fallback<Policies>> var policies: Policies = Policies()
    @Default<Fallback<Lookups>> var lookups: Lookups = Lookups()
    @Default<Fallback<Features>> var features: Features = Features()
    @Default<Fallback<Limits>> var limits: Limits = Limits()
}

/// Android's `Brand` model (renamed: `Brand` is the colour palette here).
struct BrandInfo: Model, Initable {
    @Default<DefaultBrandName> var name: String = "Darse Quran Academy"
    @Default<DefaultWebsite> var websiteUrl: String = "https://darsequranacademy.com"
    @Default<Fallback<ContactInfo>> var contact: ContactInfo = ContactInfo()
    @Default<Fallback<Social>> var social: Social = Social()
}
enum DefaultBrandName: DefaultValue { static var defaultValue: String { "Darse Quran Academy" } }
enum DefaultWebsite: DefaultValue { static var defaultValue: String { "https://darsequranacademy.com" } }

struct ContactInfo: Model, Initable {
    @Default<Empty.Text> var email: String = ""
    @Default<Empty.Text> var phone: String = ""
    @Default<Empty.Text> var whatsapp: String = ""
    @Default<Empty.Text> var whatsappDefaultMessage: String = ""
    @Default<Empty.Text> var address: String = ""
}

struct Social: Model, Initable {
    var facebookUrl: String? = nil
    var instagramUrl: String? = nil
    var youtubeUrl: String? = nil
}

struct Policies: Model, Initable {
    @Default<Empty.Text> var version: String = ""
    @Default<Empty.Text> var privacyPolicyUrl: String = ""
    @Default<Empty.Text> var termsUrl: String = ""
}

struct Lookups: Model, Initable {
    @Default<Empty.List<Country>> var countries: [Country] = []
    @Default<CountryIN> var defaultCountryCode: String = "IN"
    @Default<Empty.List<Option>> var occupations: [Option] = []
    @Default<Empty.List<String>> var fatwaCategories: [String] = []
}

struct Country: Model {
    var code: String
    var name: String
    var dialCode: String
    @Default<Empty.Text> var flag: String = ""
    @Default<Four> var localNumberMinLength: Int = 4
    @Default<Fifteen> var localNumberMaxLength: Int = 15
}

struct Option: Model { var value: String; var label: String }

struct Features: Model, Initable {
    @Default<False> var googleSignIn: Bool = false
    @Default<True> var onlinePayments: Bool = true
    @Default<False> var feeWaiverRequests: Bool = false
}

struct Limits: Model, Initable {
    @Default<Twenty> var maxBookQuantityPerOrder: Int = 20
}

// MARK: - content

struct Teacher: Model, Identifiable {
    var id: String
    var name: String
    @Default<Empty.Text> var specialization: String = ""
    @Default<Empty.Text> var bio: String = ""
    @Default<Empty.Text> var initials: String = ""
    var imageUrl: String? = nil
}

struct Course: Model, Identifiable {
    var id: String
    var title: String
    @Default<Empty.Text> var description: String = ""
    @Default<Empty.Text> var startDate: String = ""
    @Default<Empty.Text> var duration: String = ""
    @Default<Empty.Text> var level: String = ""
    @Default<Empty.Text> var category: String = ""
    @Default<Published> var status: String = "PUBLISHED"
    @Default<Zero> var priceInrPaise: Int = 0
    @Default<Zero> var monthlyFeeInrPaise: Int = 0
    var feeFrequency: String? = nil
    var teacher: Teacher? = nil
}

struct Inspiration: Model, Identifiable {
    var id: String
    @Default<Quran> var kind: String = "QURAN"
    @Default<Empty.Text> var arabicText: String = ""
    @Default<Empty.Text> var englishTranslation: String = ""
    var reference: String? = nil
}

struct ImageRef: Model {
    var id: String? = nil
    var imagePath: String
    var caption: String? = nil
}

struct Author: Model { var name: String? = nil; var image: String? = nil }

struct SiteAnnouncement: Model, Identifiable {
    var id: String
    var title: String
    @Default<Empty.Text> var body: String = ""
    var eventDate: String? = nil
    var location: String? = nil
    @Default<Empty.Text> var createdAt: String = ""
    @Default<Empty.List<ImageRef>> var images: [ImageRef] = []
}

struct BlogPost: Model, Identifiable {
    var id: String
    var title: String
    var excerpt: String? = nil
    @Default<Empty.Text> var body: String = ""
    @Default<Empty.Text> var createdAt: String = ""
    @Default<Empty.List<ImageRef>> var images: [ImageRef] = []
    var createdBy: Author? = nil
    @Default<Zero> var likeCount: Int = 0
    @Default<Zero> var commentCount: Int = 0
    @Default<False> var likedByMe: Bool = false
    @Default<Empty.List<Comment>> var comments: [Comment] = []
}

struct Comment: Model, Identifiable {
    var id: String
    var content: String
    @Default<Empty.Text> var createdAt: String = ""
    var user: CommentUser? = nil
}

struct CommentUser: Model { var id: String? = nil; var name: String? = nil; var image: String? = nil }

struct Fatwa: Model, Identifiable {
    var id: String
    var title: String
    @Default<Empty.Text> var question: String = ""
    @Default<Empty.Text> var category: String = ""
    var answer: String? = nil
    var askerName: String? = nil
    var answeredAt: String? = nil
    @Default<Empty.Text> var createdAt: String = ""
}

struct LibraryItem: Model, Identifiable {
    var id: String
    var title: String
    @Default<Empty.Text> var author: String = ""
    @Default<Empty.Text> var topic: String = ""
    @Default<Empty.Text> var level: String = ""
    @Default<Empty.Text> var language: String = ""
    var pdfUrl: String? = nil
    var imagePath: String? = nil
}

struct Book: Model, Identifiable {
    var id: String
    var title: String
    @Default<Empty.Text> var author: String = ""
    @Default<Empty.Text> var description: String = ""
    @Default<Zero> var priceInrPaise: Int = 0
    @Default<Zero> var mrpInrPaise: Int = 0
    @Default<Available> var status: String = "AVAILABLE"
    var imagePath: String? = nil
}

struct Review: Model, Identifiable {
    var id: String
    var quote: String
    var course: String? = nil
    var location: String? = nil
    var name: String? = nil
    var initials: String? = nil
    @Default<Five> var rating: Int = 5
    var status: String? = nil
    @Default<False> var featuredOnHomepage: Bool = false
    var createdAt: String? = nil
}

struct HomeResponse: Model {
    var dailyInspiration: Inspiration? = nil
    @Default<Empty.List<SiteAnnouncement>> var announcements: [SiteAnnouncement] = []
    @Default<Empty.List<Course>> var courses: [Course] = []
    @Default<Empty.List<BlogPost>> var blogPosts: [BlogPost] = []
    @Default<Empty.List<LibraryItem>> var libraryItems: [LibraryItem] = []
    @Default<Empty.List<Book>> var books: [Book] = []
    @Default<Empty.List<Fatwa>> var fatwas: [Fatwa] = []
    @Default<Empty.List<Review>> var reviews: [Review] = []
}

struct InspirationResponse: Model { var inspiration: Inspiration? = nil }

struct CourseEnrollmentState: Model {
    var id: String
    var status: String
    var rollNumber: Int? = nil
    @Default<False> var enrollmentFeePending: Bool = false
}

struct CourseDetailResponse: Model {
    var course: Course
    @Default<True> var enrollmentOpen: Bool = true
    var enrollment: CourseEnrollmentState? = nil
}

struct TeacherDetailResponse: Model {
    var teacher: Teacher
    @Default<Empty.List<Course>> var courses: [Course] = []
}

struct BlogPostResponse: Model { var post: BlogPost }
struct CommentsPage: Model { @Default<Empty.List<Comment>> var data: [Comment] = [] }
struct CommentResponse: Model { var comment: Comment }
struct ContentRequest: Model { var content: String }
struct LikeResponse: Model { var liked: Bool; var likeCount: Int }
struct FatwaResponse: Model { var fatwa: Fatwa }

struct AskFatwaRequest: Model {
    var title: String
    var question: String
    var category: String
    var askerName: String
    var askerEmail: String
}

struct LibraryItemResponse: Model { var item: LibraryItem }
struct BookResponse: Model { var book: Book }
struct AnnouncementResponse: Model { var announcement: SiteAnnouncement }

struct ContactRequest: Model {
    var name: String?
    var email: String?
    var phone: String?
    var message: String
}

// MARK: - courses

struct Enrollment: Model, Identifiable {
    var id: String
    var courseId: String
    var status: String
    var rollNumber: Int? = nil
    @Default<Empty.Text> var createdAt: String = ""
    var completedAt: String? = nil
    /// When an admin turned the request down.
    var rejectedAt: String? = nil
    var course: Course? = nil
}

struct EnrollmentsResponse: Model { @Default<Empty.List<Enrollment>> var data: [Enrollment] = [] }
struct EnrollRequest: Model { var courseId: String }

struct EnrollResponse: Model {
    @Default<True> var success: Bool = true
    @Default<False> var alreadyEnrolled: Bool = false
    var requiresEnrollmentFee: Bool? = nil
    var status: String? = nil
    var message: String? = nil
}

struct CourseAnnouncement: Model, Identifiable {
    var id: String
    var title: String
    @Default<Empty.Text> var body: String = ""
    var category: String? = nil
    @Default<Empty.Text> var authorName: String = ""
    var attachmentPath: String? = nil
    var attachmentName: String? = nil
    var enrollmentId: String? = nil
    @Default<Empty.Text> var createdAt: String = ""
}

struct CourseAnnouncementsResponse: Model {
    @Default<Empty.List<CourseAnnouncement>> var courseWide: [CourseAnnouncement] = []
    @Default<Zero> var courseWideTotal: Int = 0
    @Default<Empty.List<CourseAnnouncement>> var personal: [CourseAnnouncement] = []
    @Default<Zero> var personalTotal: Int = 0
}

struct AttendanceRecord: Model, Identifiable { var id: String; var date: String; var isPresent: Bool }

struct CourseAttendance: Model {
    var enrollmentId: String
    var courseId: String
    var rollNumber: Int? = nil
    @Default<Zero> var totalClasses: Int = 0
    @Default<Zero> var presentClasses: Int = 0
    @Default<Zero> var absentClasses: Int = 0
    @Default<Zero> var percentage: Int = 0
    @Default<Empty.List<AttendanceRecord>> var records: [AttendanceRecord] = []
}

struct AttendanceResponse: Model { @Default<Empty.List<CourseAttendance>> var attendance: [CourseAttendance] = [] }

struct GradeEntry: Model, Identifiable {
    var id: String
    var title: String
    @Default<Empty.Text> var date: String = ""
    @Default<ZeroDouble> var maxMarks: Double = 0
    var marksObtained: Double? = nil
    var percentage: Int? = nil
}

struct CourseGrades: Model {
    var enrollmentId: String
    var courseId: String
    @Default<ZeroDouble> var totalMaxMarks: Double = 0
    @Default<ZeroDouble> var totalMarksObtained: Double = 0
    @Default<Zero> var overallPercentage: Int = 0
    @Default<Empty.List<GradeEntry>> var grades: [GradeEntry] = []
}

struct GradesResponse: Model { @Default<Empty.List<CourseGrades>> var grades: [CourseGrades] = [] }

// MARK: - payments

struct PaymentSettings: Model, Initable {
    var upiId: String? = nil
    var upiNumber: String? = nil
    var upiPayeeName: String? = nil
    var bankAccountName: String? = nil
    var bankName: String? = nil
    var bankAccountNumber: String? = nil
    var bankIfsc: String? = nil
    var bankBranch: String? = nil
    @Default<False> var feeWaiverEnabled: Bool = false
}

struct PaymentSettingsResponse: Model {
    @Default<Fallback<PaymentSettings>> var settings: PaymentSettings = PaymentSettings()
}

struct QuoteCoupon: Model, Identifiable {
    var id: String
    var code: String
    var percentage: Int
    var amountPaise: Int
    var validUntil: String? = nil
}

struct PaymentQuote: Model {
    var courseId: String
    var type: String
    var canPay: Bool
    var reason: String? = nil
    @Default<Zero> var baseAmountPaise: Int = 0
    @Default<Empty.List<QuoteCoupon>> var coupons: [QuoteCoupon] = []
    var feeFrequency: String? = nil
    var feeFrequencyLabel: String? = nil
    @Default<False> var oneTimeFee: Bool = false
    @Default<Empty.List<String>> var yearOptions: [String] = []
}

struct PaymentSubmission: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var courseId: String = ""
    @Default<Empty.Text> var paymentType: String = ""
    @Default<Empty.Text> var label: String = ""
    @Default<Zero> var amountInrPaise: Int = 0
    @Default<Empty.Text> var status: String = ""
    var paymentMethod: String? = nil
    var upiTransactionId: String? = nil
    var paymentRecordId: String? = nil
    @Default<Empty.Text> var createdAt: String = ""
}

struct PaymentRecord: Model, Identifiable {
    var id: String
    var courseId: String? = nil
    @Default<Zero> var amountInrPaise: Int = 0
    @Default<Empty.Text> var paidAt: String = ""
    var paymentType: String? = nil
    var description: String? = nil
    var invoiceNumber: String? = nil
    var receiptGeneratedAt: String? = nil
}

struct PaymentHistory: Model {
    @Default<Empty.List<PaymentSubmission>> var submissions: [PaymentSubmission] = []
    @Default<Empty.List<PaymentRecord>> var records: [PaymentRecord] = []
}

struct WaiverRequest: Model, Identifiable {
    var id: String
    var courseId: String
    @Default<Empty.Text> var reason: String = ""
    @Default<PendingUpper> var status: String = "PENDING"
    var feeType: String? = nil
    @Default<Empty.Text> var createdAt: String = ""
    var course: CourseTitle? = nil
    /// The first issued coupon; [couponCodes] lists every code (two for a "both fees" waiver).
    var coupon: WaiverCoupon? = nil
    @Default<Empty.List<String>> var couponCodes: [String] = []
}

struct WaiverCoupon: Model {
    var code: String
    @Default<Zero> var percentage: Int = 0
}

struct CourseTitle: Model { var title: String? = nil }
struct WaiverRequestsResponse: Model { @Default<Empty.List<WaiverRequest>> var data: [WaiverRequest] = [] }
struct WaiverRequestBody: Model { var courseId: String; var feeType: String; var reason: String }
struct ReviewsResponse: Model { @Default<Empty.List<Review>> var data: [Review] = [] }

struct ReviewRequest: Model {
    var quote: String
    var rating: Int
    var course: String? = nil
    var location: String? = nil
}

// MARK: - bookstore

struct CartItem: Model, Identifiable {
    var bookId: String
    @Default<Empty.Text> var title: String = ""
    @Default<Empty.Text> var author: String = ""
    @Default<Zero> var priceInrPaise: Int = 0
    @Default<Zero> var mrpInrPaise: Int = 0
    var imagePath: String? = nil
    @Default<One> var quantity: Int = 1

    var id: String { bookId }
}

struct CartResponse: Model { @Default<Empty.List<CartItem>> var items: [CartItem] = [] }
struct CartLine: Model { var bookId: String; var quantity: Int }
struct CartReplace: Model { var items: [CartLine] }

struct QuoteLine: Model {
    var bookId: String
    var title: String
    var quantity: Int
    var unitPriceInrPaise: Int
    var lineTotalInrPaise: Int
}

struct CheckoutQuote: Model {
    @Default<Empty.List<QuoteLine>> var lines: [QuoteLine] = []
    @Default<Zero> var subtotalAmountInrPaise: Int = 0
    @Default<Zero> var shippingChargeInrPaise: Int = 0
    @Default<Zero> var totalAmountInrPaise: Int = 0
}

struct OrderBook: Model {
    var id: String
    @Default<Empty.Text> var title: String = ""
    @Default<Empty.Text> var author: String = ""
    var imagePath: String? = nil
}

struct OrderItem: Model, Identifiable {
    var id: String
    var bookId: String
    var quantity: Int
    var priceAtPurchaseInrPaise: Int
    var book: OrderBook? = nil
}

struct BookOrder: Model, Identifiable {
    var id: String
    @Default<Zero> var totalAmountInrPaise: Int = 0
    @Default<Zero> var shippingChargeInrPaise: Int = 0
    @Default<Empty.Text> var status: String = ""
    var deliveryAddress: String? = nil
    var deliveryPinCode: String? = nil
    var deliveryPhoneNumber: String? = nil
    var courierServiceName: String? = nil
    var trackingId: String? = nil
    @Default<Empty.Text> var createdAt: String = ""
    @Default<Empty.List<OrderItem>> var items: [OrderItem] = []
    var paymentRecordId: String? = nil
    var receiptGeneratedAt: String? = nil
}

struct OrdersResponse: Model { @Default<Empty.List<BookOrder>> var orders: [BookOrder] = [] }
struct OrderResponse: Model { var order: BookOrder }

// MARK: - notifications

struct AppNotification: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var type: String = ""
    var title: String
    var body: String? = nil
    @Default<Empty.Text> var href: String = ""
    var readAt: String? = nil
    @Default<Empty.Text> var createdAt: String = ""
}

struct NotificationResponse: Model { var notification: AppNotification }
struct MarkReadRequest: Model { var notificationId: String? = nil; var markAllRead: Bool? = nil }

// MARK: - statuses (Statuses.kt)

/// The account roles the website gives users ([SessionUser.role]).
enum Roles {
    static let user = "USER"
    static let teacher = "TEACHER"
    static let admin = "ADMIN"
    static let developer = "DEVELOPER"

    /// Admins and developers use the admin area.
    static func isAdmin(_ role: String?) -> Bool { role == admin || role == developer }
}

/// The [Enrollment.status] values the app acts on.
enum EnrollmentStatus {
    static let active = "active"
    static let completed = "completed"
    static let awaitingEnrollmentFee = "awaiting_enrollment_fee"
    static let pendingApproval = "pending_approval"
    static let rejected = "rejected"

    /// Studying or finished: the course's own screens (updates, attendance, marks, fees) are open to the student.
    static func opensLearn(_ status: String) -> Bool { status == active || status == completed }
}
