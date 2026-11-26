import Foundation

// Students (/api/v1/admin/students), ported from Android's data/staff/students/StudentsAdminApi.kt.

struct StudentRow: Model, Identifiable {
    var id: String
    var name: String? = nil
    @Default<Empty.Text> var email: String = ""
    var registrationNumber: String? = nil
    var image: String? = nil
    var gender: String? = nil
    var createdAt: String? = nil
}

struct StudentEnrollment: Model, Identifiable {
    var id: String
    var courseId: String
    @Default<Empty.Text> var courseTitle: String = ""
    var rollNumber: String? = nil
    @Default<Empty.Text> var status: String = ""
    @Default<Empty.Text> var statusLabel: String = ""
    var createdAt: String? = nil
}

struct StudentDetail: Model, Identifiable {
    var id: String
    var name: String? = nil
    @Default<Empty.Text> var email: String = ""
    var registrationNumber: String? = nil
    var image: String? = nil
    var gender: String? = nil
    var fatherName: String? = nil
    var dateOfBirth: String? = nil
    var dateOfBirthDisplay: String? = nil
    var occupation: String? = nil
    var occupationLabel: String? = nil
    var address: String? = nil
    var whatsapp: String? = nil
    var createdAt: String? = nil
    @Default<False> var profileComplete: Bool = false
    @Default<Empty.List<StudentEnrollment>> var enrollments: [StudentEnrollment] = []
}

struct StudentResponse: Model { var student: StudentDetail }

struct StudentPayment: Model, Identifiable {
    var id: String
    var paidAt: String? = nil
    @Default<Zero> var amountInrPaise: Int = 0
    var courseTitle: String? = nil
    var description: String? = nil
}

struct StudentsAdminAPI: StaffService {
    let client: APIClient

    func list(page: Int, q: String?, sort: String?) async throws -> Paged<StudentRow> {
        try await client.get("admin/students", query: ["page": "\(page)", "q": q, "sort": sort])
    }

    func get(_ id: String) async throws -> StudentResponse { try await client.get("admin/students/\(id.pathEncoded)") }

    func payments(_ id: String, page: Int = 1, pageSize: Int = 50) async throws -> Paged<StudentPayment> {
        try await client.get("admin/students/\(id.pathEncoded)/payments", query: ["page": "\(page)", "pageSize": "\(pageSize)"])
    }

    func update(_ id: String, _ form: FormBody) async throws -> ActionResponse {
        try await client.form("PATCH", "admin/students/\(id.pathEncoded)", form)
    }

    func delete(_ id: String) async throws -> ActionResponse { try await client.delete("admin/students/\(id.pathEncoded)") }

    /// The student's ID card (PDF), downloaded into the document cache as [fileName]; open it with DocumentPreview
    /// (or `ActionRunner.openFile`).
    func idCard(_ id: String, fileName: String) async throws -> URL {
        try await client.download("admin/students/\(id.pathEncoded)/id-card", fileName: fileName)
    }

    func emailIdCard(_ id: String) async throws -> ActionResponse { try await client.post("admin/students/\(id.pathEncoded)/id-card/email") }
}
