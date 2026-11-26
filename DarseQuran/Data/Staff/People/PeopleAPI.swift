import Foundation

/*
 * People: teachers, enrollments, certificates, reviews, contact inquiries and the audit log
 * (/api/v1/admin/…). Ported from Android's data/staff/people/PeopleApi.kt.
 */

// MARK: - teachers

struct TeacherRow: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var name: String = ""
    var email: String? = nil
    @Default<Empty.Text> var specialization: String = ""
    @Default<Empty.Text> var initials: String = ""
    var imageUrl: String? = nil
    @Default<True> var published: Bool = true
    var createdAt: String? = nil
}

struct TeacherCourse: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var title: String = ""
    var category: String? = nil
    @Default<Empty.Text> var status: String = ""
    @Default<Empty.Text> var statusLabel: String = ""
    @Default<Zero> var studentCount: Int = 0
}

struct TeacherDetail: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var name: String = ""
    var email: String? = nil
    @Default<Empty.Text> var specialization: String = ""
    @Default<Empty.Text> var bio: String = ""
    @Default<Empty.Text> var initials: String = ""
    var imageUrl: String? = nil
    @Default<True> var published: Bool = true
    var createdAt: String? = nil
    @Default<Empty.List<TeacherCourse>> var courses: [TeacherCourse] = []
}

struct TeacherResponse: Model { var teacher: TeacherDetail }

/// An account check: ok with the account's name, or the reason it cannot be used.
struct AccountLookup: Model {
    @Default<False> var ok: Bool = false
    var name: String? = nil
    var email: String? = nil
    var error: String? = nil
}

struct LookupResponse: Model { var lookup: AccountLookup }

struct TeachersAdminAPI: StaffService {
    let client: APIClient

    func list(page: Int, q: String?) async throws -> Paged<TeacherRow> { try await client.get("admin/teachers", query: ["page": "\(page)", "q": q]) }
    func get(_ id: String) async throws -> TeacherResponse { try await client.get("admin/teachers/\(id.pathEncoded)") }
    func lookup(email: String, excludeTeacherId: String?) async throws -> LookupResponse {
        try await client.get("admin/teachers/lookup", query: ["email": email, "excludeTeacherId": excludeTeacherId])
    }
    func create(_ form: FormBody) async throws -> ActionResponse { try await client.form("POST", "admin/teachers", form) }
    func update(_ id: String, _ form: FormBody) async throws -> ActionResponse { try await client.form("PATCH", "admin/teachers/\(id.pathEncoded)", form) }
    func delete(_ id: String) async throws -> ActionResponse { try await client.delete("admin/teachers/\(id.pathEncoded)") }
}

// MARK: - enrollments

/// A person on an enrollment, certificate or review (the id can be missing).
struct PersonRef: Model, Initable {
    var id: String? = nil
    var name: String? = nil
    @Default<Empty.Text> var email: String = ""
}

struct CourseRef: Model, Identifiable, Initable {
    var id: String
    @Default<Empty.Text> var title: String = ""

    init() { id = "" }
    init(id: String, title: String = "") { self.id = id; self.title = title }
}

struct EnrollmentRequest: Model, Identifiable {
    var id: String
    var courseId: String
    @Default<Empty.Text> var courseTitle: String = ""
    @Default<Empty.Text> var status: String = ""
    var createdAt: String? = nil
    @Default<Fallback<PersonRef>> var user: PersonRef = PersonRef()
}

/// The same list answer read for its extras: tab counts and the courses the enrol form offers.
struct EnrollmentsSummary: Model {
    @Default<Zero> var freeCount: Int = 0
    @Default<Zero> var paidCount: Int = 0
    @Default<Empty.List<CourseRef>> var enrollableCourses: [CourseRef] = []
}

struct EnrollmentsAdminAPI: StaffService {
    let client: APIClient

    func list(page: Int, q: String?, type: String?) async throws -> Paged<EnrollmentRequest> {
        try await client.get("admin/enrollments", query: ["page": "\(page)", "q": q, "type": type])
    }
    func summary(type: String? = nil, pageSize: Int = 1) async throws -> EnrollmentsSummary {
        try await client.get("admin/enrollments", query: ["type": type, "pageSize": "\(pageSize)"])
    }
    func lookup(email: String) async throws -> LookupResponse { try await client.get("admin/enrollments/lookup", query: ["email": email]) }
    func enroll(_ form: FormBody) async throws -> ActionResponse { try await client.form("POST", "admin/enrollments", form) }
    func removeEnrollment(_ id: String, courseId: String) async throws -> ActionResponse {
        try await client.delete("admin/enrollments/\(id.pathEncoded)", query: ["courseId": courseId])
    }
    func approve(_ id: String, _ form: FormBody) async throws -> ActionResponse { try await client.form("POST", "admin/enrollments/\(id.pathEncoded)/approve", form) }
    func reject(_ id: String, _ form: FormBody) async throws -> ActionResponse { try await client.form("POST", "admin/enrollments/\(id.pathEncoded)/reject", form) }
}

// MARK: - certificates

struct CertificateRow: Model, Identifiable {
    var enrollmentId: String
    var certificateNumber: String? = nil
    var certificateGeneratedAt: String? = nil
    var certificateType: String? = nil
    @Default<Empty.Text> var typeLabel: String = ""
    var certificateGrade: Int? = nil
    var certificateEmailSentAt: String? = nil
    @Default<Fallback<PersonRef>> var user: PersonRef = PersonRef()
    @Default<Fallback<CourseRef>> var course: CourseRef = CourseRef()

    var id: String { enrollmentId }
}

struct CertificateResponse: Model { var certificate: CertificateRow }

struct CertificateCandidate: Model, Identifiable {
    var id: String
    @Default<Fallback<PersonRef>> var user: PersonRef = PersonRef()
    @Default<Fallback<CourseRef>> var course: CourseRef = CourseRef()
}

struct CertificateCandidates: Model { @Default<Empty.List<CertificateCandidate>> var enrollments: [CertificateCandidate] = [] }

struct CertificatesAdminAPI: StaffService {
    let client: APIClient

    func list(page: Int, q: String?) async throws -> Paged<CertificateRow> { try await client.get("admin/certificates", query: ["page": "\(page)", "q": q]) }
    func eligible() async throws -> CertificateCandidates { try await client.get("admin/certificates/eligible") }
    func get(_ enrollmentId: String) async throws -> CertificateResponse { try await client.get("admin/certificates/\(enrollmentId.pathEncoded)") }
    func generate(_ form: FormBody) async throws -> ActionResponse { try await client.form("POST", "admin/certificates", form) }
    func delete(_ enrollmentId: String) async throws -> ActionResponse { try await client.delete("admin/certificates/\(enrollmentId.pathEncoded)") }
    /// The certificate PDF, downloaded into the document cache as [fileName].
    func pdf(_ enrollmentId: String, fileName: String) async throws -> URL {
        try await client.download("admin/certificates/\(enrollmentId.pathEncoded)/pdf", fileName: fileName)
    }
    func email(_ enrollmentId: String) async throws -> ActionResponse { try await client.post("admin/certificates/\(enrollmentId.pathEncoded)/email") }
}

// MARK: - reviews

struct StudentReviewRow: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var quote: String = ""
    var course: String? = nil
    @Default<Empty.Text> var courseLabel: String = ""
    var location: String? = nil
    @Default<Zero> var rating: Int = 0
    @Default<Empty.Text> var status: String = ""
    @Default<Empty.Text> var statusLabel: String = ""
    @Default<False> var featuredOnHomepage: Bool = false
    var createdAt: String? = nil
    @Default<Fallback<PersonRef>> var user: PersonRef = PersonRef()
}

struct ReviewsSummary: Model {
    @Default<Zero> var pendingCount: Int = 0
    @Default<Zero> var approvedCount: Int = 0
    @Default<Zero> var featuredCount: Int = 0
    @Default<Zero> var featuredMax: Int = 0
}

struct ReviewResponse: Model {
    var review: StudentReviewRow
    @Default<Zero> var featuredCount: Int = 0
    @Default<Zero> var featuredMax: Int = 0
    @Default<False> var canFeature: Bool = false
}

struct ReviewsAdminAPI: StaffService {
    let client: APIClient

    func list(page: Int, q: String?, type: String?) async throws -> Paged<StudentReviewRow> {
        try await client.get("admin/review-approvals", query: ["page": "\(page)", "q": q, "type": type])
    }
    func summary(pageSize: Int = 1) async throws -> ReviewsSummary { try await client.get("admin/review-approvals", query: ["pageSize": "\(pageSize)"]) }
    func get(_ id: String) async throws -> ReviewResponse { try await client.get("admin/review-approvals/\(id.pathEncoded)") }
    func approve(_ id: String, _ form: FormBody) async throws -> ActionResponse { try await client.form("POST", "admin/review-approvals/\(id.pathEncoded)/approve", form) }
    func reject(_ id: String) async throws -> ActionResponse { try await client.post("admin/review-approvals/\(id.pathEncoded)/reject") }
    func saveHomepage(_ id: String, _ form: FormBody) async throws -> ActionResponse { try await client.form("PATCH", "admin/review-approvals/\(id.pathEncoded)", form) }
    func delete(_ id: String) async throws -> ActionResponse { try await client.delete("admin/review-approvals/\(id.pathEncoded)") }
}

// MARK: - contact inquiries

struct Replier: Model {
    var name: String? = nil
    var email: String? = nil
}

struct ContactInquiry: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var name: String = ""
    @Default<Empty.Text> var email: String = ""
    @Default<Empty.Text> var phone: String = ""
    @Default<Empty.Text> var message: String = ""
    var reply: String? = nil
    @Default<Empty.Text> var status: String = ""
    @Default<Empty.Text> var statusLabel: String = ""
    var repliedAt: String? = nil
    var repliedBy: Replier? = nil
    var createdAt: String? = nil
}

struct ContactInquiryResponse: Model { var inquiry: ContactInquiry }

struct ContactInquiriesAPI: StaffService {
    let client: APIClient

    func list(page: Int, q: String?, filter: String?) async throws -> Paged<ContactInquiry> {
        try await client.get("admin/contact-inquiries", query: ["page": "\(page)", "q": q, "filter": filter])
    }
    func get(_ id: String) async throws -> ContactInquiryResponse { try await client.get("admin/contact-inquiries/\(id.pathEncoded)") }
    func reply(_ id: String, _ form: FormBody) async throws -> ActionResponse { try await client.form("POST", "admin/contact-inquiries/\(id.pathEncoded)/reply", form) }
    func delete(_ id: String) async throws -> ActionResponse { try await client.delete("admin/contact-inquiries/\(id.pathEncoded)") }
}

// MARK: - audit log

struct AuditEntry: Model, Identifiable {
    var id: String
    var createdAt: String? = nil
    @Default<SystemActor> var actor: String = "system"
    @Default<Empty.Text> var action: String = ""
    @Default<Empty.Text> var entity: String = ""
    var entityId: String? = nil
    var reason: String? = nil
    var before: JSONValue? = nil
    var after: JSONValue? = nil
}

struct AuditEntities: Model { @Default<Empty.List<String>> var entities: [String] = [] }

struct AuditLogAPI: StaffService {
    let client: APIClient

    func list(page: Int, entity: String?, entityId: String?, actor: String?) async throws -> Paged<AuditEntry> {
        try await client.get("admin/audit-log", query: ["page": "\(page)", "entity": entity, "entityId": entityId, "actor": actor])
    }
    func entities(pageSize: Int = 1) async throws -> AuditEntities { try await client.get("admin/audit-log", query: ["pageSize": "\(pageSize)"]) }
}
