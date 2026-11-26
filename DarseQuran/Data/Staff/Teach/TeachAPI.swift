import Foundation

// The teacher portal (/api/v1/teacher), ported from Android's data/staff/teach/TeachApi.kt.

struct TeacherCourseRow: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var title: String = ""
    @Default<Empty.Text> var status: String = ""
    @Default<Empty.Text> var statusLabel: String = ""
    @Default<Empty.Text> var level: String = ""
    @Default<Empty.Text> var category: String = ""
    var startDate: String? = nil
    var duration: String? = nil
    @Default<Empty.Text> var description: String = ""
    @Default<Zero> var studentCount: Int = 0
}

struct TeacherProfile: Model, Initable {
    @Default<Empty.Text> var name: String = ""
    @Default<Empty.Text> var specialization: String = ""
    @Default<Empty.Text> var email: String = ""
}

struct TeacherStats: Model, Initable {
    @Default<Zero> var totalCourses: Int = 0
    @Default<Zero> var totalStudents: Int = 0
}

/// The first page of the teacher's courses, with the welcome header's name and counts (one request for both).
struct TeacherHome: Model {
    @Default<Empty.List<TeacherCourseRow>> var data: [TeacherCourseRow] = []
    @Default<Zero> var totalCount: Int = 0
    @Default<Fallback<TeacherProfile>> var teacher: TeacherProfile = TeacherProfile()
    @Default<Fallback<TeacherStats>> var stats: TeacherStats = TeacherStats()
}

struct TeacherEnrollment: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var status: String = ""
    @Default<Empty.Text> var statusLabel: String = ""
    @Default<Dash> var rollNumberLabel: String = "—"
    var createdAt: String? = nil
    var completedAt: String? = nil
}

struct TeacherStudentProfile: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var name: String = ""
    @Default<Empty.Text> var email: String = ""
    var fatherName: String? = nil
    var dateOfBirthDisplay: String? = nil
    var occupationLabel: String? = nil
    var address: String? = nil
    var whatsapp: String? = nil
    var createdAt: String? = nil
}

struct TeacherStudentResponse: Model {
    var course: CourseHeader
    var enrollment: TeacherEnrollment
    var student: TeacherStudentProfile
}

struct TeachAPI: StaffService {
    let client: APIClient

    func home(page: Int = 1) async throws -> TeacherHome { try await client.get("teacher/courses", query: ["page": "\(page)"]) }
    func courses(page: Int) async throws -> Paged<TeacherCourseRow> { try await client.get("teacher/courses", query: ["page": "\(page)"]) }
    func students(_ id: String, page: Int) async throws -> Paged<RosterRow> {
        try await client.get("teacher/courses/\(id.pathEncoded)/students", query: ["page": "\(page)"])
    }
    func student(_ id: String, enrollmentId: String) async throws -> TeacherStudentResponse {
        try await client.get("teacher/courses/\(id.pathEncoded)/students/\(enrollmentId.pathEncoded)")
    }
}
