import Foundation

/*
 * Courses: the admin course list and form (/api/v1/admin/courses), and the course tools shared by the admin and
 * teacher portals (/api/v1/{admin|teacher}/courses/{id}/…). Ported from Android's data/staff/courses/CoursesApi.kt.
 *
 * Renamed where the student app already has the name: CourseAnnouncement → StaffCourseAnnouncement,
 * AnnouncementResponse → StaffAnnouncementResponse, AttendanceRecord → StaffAttendanceRecord.
 */

/// Which website portal a course screen stands for (the routes carry it).
enum Portal: String, Hashable, Sendable, CaseIterable {
    case admin, teacher

    /// The path segment: "admin" or "teacher".
    var path: String { rawValue }

    /// An unknown value gets the teacher portal, the one with fewer rights, never the admin one.
    static func of(_ path: String) -> Portal { Portal(rawValue: path) ?? .teacher }
}

// MARK: - admin course list and form

struct AdminCourseRow: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var title: String = ""
    @Default<Empty.Text> var category: String = ""
    @Default<Empty.Text> var level: String = ""
    var teacherName: String? = nil
    var duration: String? = nil
    @Default<Zero> var registrationFeePaise: Int = 0
    @Default<Zero> var feePaise: Int = 0
    @Default<Monthly> var feeFrequency: String = "MONTHLY"
    @Default<Empty.Text> var feeFrequencyLabel: String = ""
    @Default<Zero> var studentCount: Int = 0
    @Default<Empty.Text> var status: String = ""
    @Default<Empty.Text> var statusLabel: String = ""
    @Default<False> var featured: Bool = false
}

struct CourseHeader: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var title: String = ""
    @Default<Empty.Text> var status: String = ""
    @Default<Empty.Text> var statusLabel: String = ""
    @Default<Empty.Text> var category: String = ""
    @Default<Empty.Text> var level: String = ""
    var startDate: String? = nil
    var duration: String? = nil
    var teacherName: String? = nil
}

struct CourseFormValues: Model, Initable {
    @Default<Empty.Text> var title: String = ""
    @Default<Empty.Text> var description: String = ""
    @Default<Empty.Text> var startDate: String = ""
    @Default<Empty.Text> var duration: String = ""
    @Default<Empty.Text> var category: String = ""
    @Default<Empty.Text> var teacherId: String = ""
    @Default<Beginner> var level: String = "Beginner"
    @Default<Zero> var enrollmentFeeInr: Int = 0
    @Default<Zero> var monthlyFeeInr: Int = 0
    @Default<Monthly> var feeFrequency: String = "MONTHLY"
    @Default<Published> var status: String = "PUBLISHED"
    @Default<False> var featuredOnHomepage: Bool = false
}

struct TeacherOption: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var name: String = ""
    @Default<Empty.Text> var specialization: String = ""
}

/// A value and its label; the label is the value when the server leaves it out.
struct LevelOption: Model {
    var value: String
    var label: String

    init(value: String, label: String? = nil) { self.value = value; self.label = label ?? value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = try c.decode(String.self, forKey: .value)
        label = c.lenient(.label, or: value)
    }
}

struct StatusOption: Model {
    var value: String
    var label: String
    var description: String

    init(value: String, label: String? = nil, description: String = "") {
        self.value = value
        self.label = label ?? value
        self.description = description
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = try c.decode(String.self, forKey: .value)
        label = c.lenient(.label, or: value)
        description = c.lenient(.description, or: "")
    }
}

/// A value and its label; the label is the value when the server leaves it out.
struct ValueLabel: Model {
    var value: String
    var label: String

    init(value: String, label: String? = nil) { self.value = value; self.label = label ?? value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = try c.decode(String.self, forKey: .value)
        label = c.lenient(.label, or: value)
    }
}

struct CourseFormOptions: Model, Initable {
    @Default<Empty.List<TeacherOption>> var teachers: [TeacherOption] = []
    @Default<Empty.List<String>> var categories: [String] = []
    @Default<Empty.List<LevelOption>> var levels: [LevelOption] = []
    @Default<Empty.List<StatusOption>> var statuses: [StatusOption] = []
    @Default<Empty.List<ValueLabel>> var feeFrequencies: [ValueLabel] = []
    @Default<Zero> var featuredCount: Int = 0
    @Default<Six> var featuredMax: Int = 6
}

struct CourseFormResponse: Model {
    var course: CourseHeader? = nil
    @Default<Fallback<CourseFormValues>> var values: CourseFormValues = CourseFormValues()
    @Default<Fallback<CourseFormOptions>> var options: CourseFormOptions = CourseFormOptions()
}

/// One student of a course's roster (admin roster and the teacher's student list).
struct RosterRow: Model, Identifiable {
    var enrollmentId: String
    var userId: String? = nil
    var name: String? = nil
    @Default<Empty.Text> var email: String = ""
    var rollNumber: Int? = nil
    @Default<Dash> var rollNumberLabel: String = "—"
    var status: String? = nil
    var statusLabel: String? = nil

    var id: String { enrollmentId }
}

struct AdminCoursesAPI: StaffService {
    let client: APIClient

    func list(page: Int, q: String?) async throws -> Paged<AdminCourseRow> { try await client.get("admin/courses", query: ["page": "\(page)", "q": q]) }
    func newForm() async throws -> CourseFormResponse { try await client.get("admin/courses/new") }
    func get(_ id: String) async throws -> CourseFormResponse { try await client.get("admin/courses/\(id.pathEncoded)") }
    func create(_ form: FormBody) async throws -> ActionResponse { try await client.form("POST", "admin/courses", form) }
    func update(_ id: String, _ form: FormBody) async throws -> ActionResponse { try await client.form("PATCH", "admin/courses/\(id.pathEncoded)", form) }
    func delete(_ id: String) async throws -> ActionResponse { try await client.delete("admin/courses/\(id.pathEncoded)") }
    func roster(_ id: String, page: Int, q: String?) async throws -> Paged<RosterRow> {
        try await client.get("admin/courses/\(id.pathEncoded)/students", query: ["page": "\(page)", "q": q])
    }

    /// A student's attendance or grade card ([kind] "attendance" or "grades") as a PDF, downloaded as [fileName].
    func card(_ id: String, kind: String, enrollmentId: String, fileName: String) async throws -> URL {
        try await client.download("admin/courses/\(id.pathEncoded)/\(kind.pathEncoded)/student/\(enrollmentId.pathEncoded)/card", fileName: fileName)
    }

    func emailCard(_ id: String, kind: String, enrollmentId: String) async throws -> ActionResponse {
        try await client.post("admin/courses/\(id.pathEncoded)/\(kind.pathEncoded)/student/\(enrollmentId.pathEncoded)/card/email")
    }
}

// MARK: - shared course tools

struct CourseHeaderResponse: Model { var course: CourseHeader }

/// A course announcement, or a teacher's private message to one student (Android's CourseAnnouncement).
struct StaffCourseAnnouncement: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var category: String = ""
    @Default<Empty.Text> var categoryLabel: String = ""
    @Default<Empty.Text> var title: String = ""
    @Default<Empty.Text> var body: String = ""
    @Default<Empty.Text> var authorName: String = ""
    @Default<False> var postedByAdmin: Bool = false
    var createdAt: String? = nil
    var updatedAt: String? = nil
    @Default<False> var edited: Bool = false
    var attachmentPath: String? = nil
    var attachmentName: String? = nil
    @Default<True> var canManage: Bool = true
}

/// Android's AnnouncementResponse (courses).
struct StaffAnnouncementResponse: Model {
    var announcement: StaffCourseAnnouncement
    @Default<Empty.List<ValueLabel>> var categories: [ValueLabel] = []
}

struct AttendanceDay: Model, Identifiable {
    var id: String
    var date: String
    var dateLabel: String
    var present: Int
    var absent: Int
    var total: Int

    init(id: String, date: String, dateLabel: String? = nil, present: Int = 0, absent: Int = 0, total: Int = 0) {
        self.id = id; self.date = date; self.dateLabel = dateLabel ?? date
        self.present = present; self.absent = absent; self.total = total
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        date = try c.decode(String.self, forKey: .date)
        dateLabel = c.lenient(.dateLabel, or: date)
        present = c.lenient(.present, or: 0)
        absent = c.lenient(.absent, or: 0)
        total = c.lenient(.total, or: 0)
    }
}

struct AttendanceListResponse: Model {
    var course: CourseHeader? = nil
    @Default<Empty.List<AttendanceDay>> var data: [AttendanceDay] = []
}

/// A student to mark or grade; [isPresent] / [marksObtained] are set when a saved day or grade card is read.
struct GradableStudent: Model, Identifiable {
    var enrollmentId: String
    var rollNumber: Int? = nil
    @Default<Dash> var rollNumberLabel: String = "—"
    var name: String? = nil
    @Default<Empty.Text> var email: String = ""
    var isPresent: Bool? = nil
    var marksObtained: Double? = nil

    var id: String { enrollmentId }
}

struct StudentsResponse: Model { @Default<Empty.List<GradableStudent>> var data: [GradableStudent] = [] }

struct AttendanceDayDetail: Model {
    var date: String
    var dateLabel: String
    var present: Int
    var absent: Int
    var total: Int
    var records: [GradableStudent]

    init(date: String, dateLabel: String? = nil, present: Int = 0, absent: Int = 0, total: Int = 0, records: [GradableStudent] = []) {
        self.date = date; self.dateLabel = dateLabel ?? date
        self.present = present; self.absent = absent; self.total = total; self.records = records
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        dateLabel = c.lenient(.dateLabel, or: date)
        present = c.lenient(.present, or: 0)
        absent = c.lenient(.absent, or: 0)
        total = c.lenient(.total, or: 0)
        records = c.lenient(.records, or: [])
    }
}

struct AttendanceMark: Model { var enrollmentId: String; var isPresent: Bool }
struct AttendanceSave: Model { var records: [AttendanceMark] }

struct ReportStudent: Model {
    var enrollmentId: String
    var name: String? = nil
    @Default<Empty.Text> var email: String = ""
    @Default<Dash> var rollNumberLabel: String = "—"
}

struct AttendanceSummary: Model, Initable {
    @Default<Zero> var total: Int = 0
    @Default<Zero> var present: Int = 0
    @Default<Zero> var absent: Int = 0
    @Default<Zero> var percentage: Int = 0
}

/// One day of a student's attendance report (Android's AttendanceRecord in courses).
struct StaffAttendanceRecord: Model, Identifiable {
    var id: String
    var date: String
    var dateLabel: String
    var isPresent: Bool

    init(id: String, date: String, dateLabel: String? = nil, isPresent: Bool) {
        self.id = id; self.date = date; self.dateLabel = dateLabel ?? date; self.isPresent = isPresent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        date = try c.decode(String.self, forKey: .date)
        dateLabel = c.lenient(.dateLabel, or: date)
        isPresent = try c.decode(Bool.self, forKey: .isPresent)
    }
}

struct AttendanceReport: Model {
    var student: ReportStudent
    @Default<Empty.Text> var courseTitle: String = ""
    @Default<Fallback<AttendanceSummary>> var summary: AttendanceSummary = AttendanceSummary()
    @Default<Empty.List<StaffAttendanceRecord>> var records: [StaffAttendanceRecord] = []
    @Default<False> var canDownloadCard: Bool = false
}

struct GradeCardRow: Model, Identifiable {
    var id: String
    var title: String
    var date: String
    var dateLabel: String
    var maxMarks: Int
    var graded: Int

    init(id: String, title: String = "", date: String = "", dateLabel: String? = nil, maxMarks: Int = 0, graded: Int = 0) {
        self.id = id; self.title = title; self.date = date; self.dateLabel = dateLabel ?? date; self.maxMarks = maxMarks; self.graded = graded
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = c.lenient(.title, or: "")
        date = c.lenient(.date, or: "")
        dateLabel = c.lenient(.dateLabel, or: date)
        maxMarks = c.lenient(.maxMarks, or: 0)
        graded = c.lenient(.graded, or: 0)
    }
}

struct GradeListResponse: Model {
    var course: CourseHeader? = nil
    @Default<Empty.List<GradeCardRow>> var data: [GradeCardRow] = []
}

struct GradeDetail: Model, Identifiable {
    var id: String
    var title: String
    var date: String
    var dateLabel: String
    var maxMarks: Int
    var records: [GradableStudent]

    init(id: String, title: String = "", date: String = "", dateLabel: String? = nil, maxMarks: Int = 0, records: [GradableStudent] = []) {
        self.id = id; self.title = title; self.date = date; self.dateLabel = dateLabel ?? date; self.maxMarks = maxMarks; self.records = records
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = c.lenient(.title, or: "")
        date = c.lenient(.date, or: "")
        dateLabel = c.lenient(.dateLabel, or: date)
        maxMarks = c.lenient(.maxMarks, or: 0)
        records = c.lenient(.records, or: [])
    }
}

struct GradeResponse: Model { var grade: GradeDetail }

/// A student's marks; nil (sent as JSON null, as on Android) when not graded.
struct GradeMark: Model {
    var enrollmentId: String
    var marksObtained: Double?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enrollmentId, forKey: .enrollmentId)
        try c.encode(marksObtained, forKey: .marksObtained)
    }
}

struct GradeSave: Model {
    var title: String
    var date: String
    var maxMarks: Int
    var records: [GradeMark]
}

struct GradeSummary: Model, Initable {
    @Default<Zero> var exams: Int = 0
    @Default<ZeroDouble> var obtained: Double = 0
    @Default<Zero> var max: Int = 0
    @Default<Zero> var percentage: Int = 0
}

struct GradeRecord: Model, Identifiable {
    var id: String
    var title: String
    var date: String
    var dateLabel: String
    var maxMarks: Int
    var marksObtained: Double

    init(id: String, title: String = "", date: String = "", dateLabel: String? = nil, maxMarks: Int = 0, marksObtained: Double = 0) {
        self.id = id; self.title = title; self.date = date; self.dateLabel = dateLabel ?? date
        self.maxMarks = maxMarks; self.marksObtained = marksObtained
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = c.lenient(.title, or: "")
        date = c.lenient(.date, or: "")
        dateLabel = c.lenient(.dateLabel, or: date)
        maxMarks = c.lenient(.maxMarks, or: 0)
        marksObtained = c.lenient(.marksObtained, or: 0)
    }
}

struct GradeReport: Model {
    var student: ReportStudent
    @Default<Empty.Text> var courseTitle: String = ""
    @Default<Fallback<GradeSummary>> var summary: GradeSummary = GradeSummary()
    @Default<Empty.List<GradeRecord>> var records: [GradeRecord] = []
    @Default<False> var canDownloadCard: Bool = false
}

/// The course tools of both portals: [portal] is .admin or .teacher. Teachers reach only their own courses.
struct CourseToolsAPI: StaffService {
    let client: APIClient

    private func base(_ portal: Portal, _ id: String) -> String { "\(portal.path)/courses/\(id.pathEncoded)" }

    func course(_ portal: Portal, _ id: String) async throws -> CourseHeaderResponse { try await client.get(base(portal, id)) }

    // announcements (enrollmentId: a teacher's private messages to one student)
    func announcements(_ portal: Portal, _ id: String, page: Int, q: String?) async throws -> Paged<StaffCourseAnnouncement> {
        try await client.get("\(base(portal, id))/announcements", query: ["page": "\(page)", "q": q])
    }

    func messages(_ portal: Portal, _ id: String, enrollmentId: String, page: Int) async throws -> Paged<StaffCourseAnnouncement> {
        try await client.get("\(base(portal, id))/students/\(enrollmentId.pathEncoded)/announcements", query: ["page": "\(page)"])
    }

    /// [scope] is [announcementScope]: "" for course-wide posts, "students/{id}/" for a student's messages.
    func announcement(_ portal: Portal, _ id: String, scope: String, announcementId: String) async throws -> StaffAnnouncementResponse {
        try await client.get("\(base(portal, id))/\(scope)announcements/\(announcementId.pathEncoded)")
    }

    func createAnnouncement(_ portal: Portal, _ id: String, scope: String, _ form: FormBody) async throws -> ActionResponse {
        try await client.form("POST", "\(base(portal, id))/\(scope)announcements", form)
    }

    func updateAnnouncement(_ portal: Portal, _ id: String, scope: String, announcementId: String, _ form: FormBody) async throws -> ActionResponse {
        try await client.form("PATCH", "\(base(portal, id))/\(scope)announcements/\(announcementId.pathEncoded)", form)
    }

    func deleteAnnouncement(_ portal: Portal, _ id: String, scope: String, announcementId: String) async throws -> ActionResponse {
        try await client.delete("\(base(portal, id))/\(scope)announcements/\(announcementId.pathEncoded)")
    }

    // attendance
    func attendance(_ portal: Portal, _ id: String) async throws -> AttendanceListResponse { try await client.get("\(base(portal, id))/attendance") }
    func attendanceStudents(_ portal: Portal, _ id: String) async throws -> StudentsResponse { try await client.get("\(base(portal, id))/attendance/students") }
    func attendanceDay(_ portal: Portal, _ id: String, date: String) async throws -> AttendanceDayDetail {
        try await client.get("\(base(portal, id))/attendance/\(date.pathEncoded)")
    }
    func saveAttendance(_ portal: Portal, _ id: String, date: String, _ body: AttendanceSave) async throws -> ActionResponse {
        try await client.put("\(base(portal, id))/attendance/\(date.pathEncoded)", body)
    }
    func deleteAttendance(_ portal: Portal, _ id: String, date: String) async throws -> ActionResponse {
        try await client.delete("\(base(portal, id))/attendance/\(date.pathEncoded)")
    }
    func attendanceReport(_ portal: Portal, _ id: String, enrollmentId: String) async throws -> AttendanceReport {
        try await client.get("\(base(portal, id))/attendance/student/\(enrollmentId.pathEncoded)")
    }

    // grade cards
    func grades(_ portal: Portal, _ id: String) async throws -> GradeListResponse { try await client.get("\(base(portal, id))/grades") }
    func gradeStudents(_ portal: Portal, _ id: String) async throws -> StudentsResponse { try await client.get("\(base(portal, id))/grades/students") }
    func grade(_ portal: Portal, _ id: String, gradeId: String) async throws -> GradeResponse {
        try await client.get("\(base(portal, id))/grades/\(gradeId.pathEncoded)")
    }
    func createGrade(_ portal: Portal, _ id: String, _ body: GradeSave) async throws -> ActionResponse {
        try await client.post("\(base(portal, id))/grades", body)
    }
    func updateGrade(_ portal: Portal, _ id: String, gradeId: String, _ body: GradeSave) async throws -> ActionResponse {
        try await client.put("\(base(portal, id))/grades/\(gradeId.pathEncoded)", body)
    }
    func deleteGrade(_ portal: Portal, _ id: String, gradeId: String) async throws -> ActionResponse {
        try await client.delete("\(base(portal, id))/grades/\(gradeId.pathEncoded)")
    }
    func gradeReport(_ portal: Portal, _ id: String, enrollmentId: String) async throws -> GradeReport {
        try await client.get("\(base(portal, id))/grades/student/\(enrollmentId.pathEncoded)")
    }
}

/// The URL piece between the course and "announcements": "" for course-wide posts, "students/{id}/" for a student's
/// messages.
func announcementScope(_ enrollmentId: String?) -> String {
    guard let enrollmentId else { return "" }
    return "students/\(enrollmentId.pathEncoded)/"
}
