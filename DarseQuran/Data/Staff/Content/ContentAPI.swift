import Foundation

/*
 * Website content: site announcements, blogs and their approvals, fatwa, the digital library, verse & hadith of the
 * day, and the teacher portal's blog posts and fatwa answers. Ported from Android's data/staff/content/ContentApi.kt.
 *
 * Renamed where the student app already has the name: FatwaResponse → FatwaAdminResponse,
 * InspirationResponse → InspirationAdminResponse.
 */

struct ContentImage: Model, Identifiable {
    var id: String
    var imagePath: String
    var caption: String? = nil
    var sortOrder: Int? = nil
}

/// Homepage slots and image limits, read from a list endpoint for the "new" forms.
struct ContentLimits: Model {
    @Default<Zero> var featuredCount: Int = 0
    @Default<Four> var featuredMax: Int = 4
    @Default<Five> var maxImages: Int = 5
}

// MARK: - announcements

struct AnnouncementRow: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var title: String = ""
    var eventDate: String? = nil
    var location: String? = nil
    @Default<False> var published: Bool = false
    @Default<False> var showOnHomepage: Bool = false
    @Default<Empty.Text> var statusLabel: String = ""
    @Default<Zero> var imageCount: Int = 0
    var thumbnail: String? = nil
    var createdBy: String? = nil
    var createdAt: String? = nil
}

struct AnnouncementDetail: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var title: String = ""
    @Default<Empty.Text> var body: String = ""
    var eventDate: String? = nil
    var eventDateInput: String? = nil
    var location: String? = nil
    @Default<True> var published: Bool = true
    @Default<False> var showOnHomepage: Bool = false
    @Default<Empty.Text> var statusLabel: String = ""
    @Default<Empty.List<ContentImage>> var images: [ContentImage] = []
    var createdBy: String? = nil
    var createdAt: String? = nil
    var updatedAt: String? = nil
    var publicPath: String? = nil
}

struct SiteAnnouncementAdminResponse: Model {
    var announcement: AnnouncementDetail
    @Default<Zero> var featuredCount: Int = 0
    @Default<Four> var featuredMax: Int = 4
    @Default<Five> var maxImages: Int = 5
}

// MARK: - blogs

struct BlogRow: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var title: String = ""
    var excerpt: String? = nil
    @Default<Empty.Text> var approvalStatus: String = ""
    @Default<False> var published: Bool = false
    @Default<Empty.Text> var statusLabel: String = ""
    @Default<False> var featuredOnHomepage: Bool = false
    @Default<Zero> var imageCount: Int = 0
    var thumbnail: String? = nil
    var authorName: String? = nil
    var authorEmail: String? = nil
    var createdAt: String? = nil
    var updatedAt: String? = nil
    var publicPath: String? = nil
    @Default<False> var canEdit: Bool = false
    @Default<False> var canDelete: Bool = false
}

struct BlogDetail: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var title: String = ""
    var excerpt: String? = nil
    @Default<Empty.Text> var body: String = ""
    @Default<Empty.Text> var approvalStatus: String = ""
    @Default<False> var published: Bool = false
    @Default<Empty.Text> var statusLabel: String = ""
    @Default<False> var featuredOnHomepage: Bool = false
    @Default<Empty.List<ContentImage>> var images: [ContentImage] = []
    var authorName: String? = nil
    var authorEmail: String? = nil
    var createdAt: String? = nil
    var updatedAt: String? = nil
    var publicPath: String? = nil
    /// Admin: a teacher's submission, whose text and images cannot be changed.
    @Default<False> var contentReadOnly: Bool = false
    /// Teacher: false once the post is approved.
    @Default<True> var canEdit: Bool = true
    @Default<True> var canDelete: Bool = true
}

struct BlogResponse: Model {
    var post: BlogDetail
    @Default<Zero> var featuredCount: Int = 0
    @Default<Four> var featuredMax: Int = 4
    @Default<Ten> var maxImages: Int = 10
}

// MARK: - fatwa

struct FatwaRow: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var title: String = ""
    @Default<Empty.Text> var category: String = ""
    @Default<Empty.Text> var approvalStatus: String = ""
    @Default<False> var answered: Bool = false
    @Default<Empty.Text> var statusLabel: String = ""
    @Default<False> var featuredOnHomepage: Bool = false
    var createdAt: String? = nil
    var answeredAt: String? = nil
    var publicPath: String? = nil
    var askerName: String? = nil
    var askerEmail: String? = nil
    @Default<False> var anonymous: Bool = false
}

struct FatwaDetail: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var title: String = ""
    @Default<Empty.Text> var category: String = ""
    @Default<Empty.Text> var approvalStatus: String = ""
    @Default<False> var answered: Bool = false
    @Default<Empty.Text> var statusLabel: String = ""
    @Default<False> var featuredOnHomepage: Bool = false
    var createdAt: String? = nil
    var answeredAt: String? = nil
    var publicPath: String? = nil
    var askerName: String? = nil
    var askerEmail: String? = nil
    @Default<False> var anonymous: Bool = false
    @Default<Empty.Text> var question: String = ""
    var answer: String? = nil
    /// Teacher: false while the answer awaits review and once it is approved.
    @Default<True> var canEdit: Bool = true
}

/// Android's FatwaResponse (staff).
struct FatwaAdminResponse: Model {
    var question: FatwaDetail
    @Default<Zero> var featuredCount: Int = 0
    @Default<Four> var featuredMax: Int = 4
}

// MARK: - library

struct LibraryItemDto: Model, Identifiable {
    var id: String
    @Default<Empty.Text> var title: String = ""
    @Default<Empty.Text> var author: String = ""
    @Default<Empty.Text> var topic: String = ""
    @Default<Beginner> var level: String = "Beginner"
    @Default<Empty.Text> var language: String = ""
    var pdfUrl: String? = nil
    var imagePath: String? = nil
    @Default<True> var published: Bool = true
    @Default<Empty.Text> var statusLabel: String = ""
    @Default<False> var featuredOnHomepage: Bool = false
    var createdAt: String? = nil
    var updatedAt: String? = nil
}

struct LibraryOptions: Model {
    @Default<Empty.List<String>> var topics: [String] = []
    @Default<Empty.List<String>> var languages: [String] = []
    @Default<LibraryLevels> var levels: [String] = ["Beginner", "Intermediate", "Advanced"]
    @Default<Zero> var featuredCount: Int = 0
    @Default<Four> var featuredMax: Int = 4
}

struct LibraryResponse: Model {
    var item: LibraryItemDto
    @Default<Empty.List<String>> var topics: [String] = []
    @Default<Empty.List<String>> var languages: [String] = []
    @Default<LibraryLevels> var levels: [String] = ["Beginner", "Intermediate", "Advanced"]
    @Default<Zero> var featuredCount: Int = 0
    @Default<Four> var featuredMax: Int = 4

    var options: LibraryOptions {
        LibraryOptions(topics: topics, languages: languages, levels: levels, featuredCount: featuredCount, featuredMax: featuredMax)
    }
}

// MARK: - verse & hadith

struct InspirationDto: Model, Identifiable {
    var id: String
    @Default<Quran> var kind: String = "QURAN"
    @Default<Empty.Text> var arabicText: String = ""
    @Default<Empty.Text> var englishTranslation: String = ""
    var reference: String? = nil
    @Default<False> var published: Bool = false
    var createdAt: String? = nil
    var updatedAt: String? = nil
    @Default<Empty.Text> var kindLabel: String = ""
    @Default<Empty.Text> var statusLabel: String = ""
    @Default<False> var onHomepage: Bool = false
}

/// Android's InspirationResponse (staff).
struct InspirationAdminResponse: Model { var item: InspirationDto }

// MARK: - API

struct ContentAPI: StaffService {
    let client: APIClient

    // Site announcements
    func announcements(page: Int, q: String?) async throws -> Paged<AnnouncementRow> { try await client.get("admin/announcements", query: ["page": "\(page)", "q": q]) }
    func announcementLimits() async throws -> ContentLimits { try await client.get("admin/announcements", query: ["pageSize": "1"]) }
    func announcement(_ id: String) async throws -> SiteAnnouncementAdminResponse { try await client.get("admin/announcements/\(id.pathEncoded)") }
    func createAnnouncement(_ form: FormBody) async throws -> ActionResponse { try await client.form("POST", "admin/announcements", form) }
    func updateAnnouncement(_ id: String, _ form: FormBody) async throws -> ActionResponse { try await client.form("PATCH", "admin/announcements/\(id.pathEncoded)", form) }
    func deleteAnnouncement(_ id: String) async throws -> ActionResponse { try await client.delete("admin/announcements/\(id.pathEncoded)") }
    func toggleAnnouncementHomepage(_ id: String) async throws -> ActionResponse { try await client.post("admin/announcements/\(id.pathEncoded)/homepage") }

    // Blogs (admin)
    func blogs(page: Int, q: String?) async throws -> Paged<BlogRow> { try await client.get("admin/blogs", query: ["page": "\(page)", "q": q]) }
    func blogLimits() async throws -> ContentLimits { try await client.get("admin/blogs", query: ["pageSize": "1"]) }
    func blog(_ id: String) async throws -> BlogResponse { try await client.get("admin/blogs/\(id.pathEncoded)") }
    func createBlog(_ form: FormBody) async throws -> ActionResponse { try await client.form("POST", "admin/blogs", form) }
    func updateBlog(_ id: String, _ form: FormBody) async throws -> ActionResponse { try await client.form("PATCH", "admin/blogs/\(id.pathEncoded)", form) }
    func deleteBlog(_ id: String) async throws -> ActionResponse { try await client.delete("admin/blogs/\(id.pathEncoded)") }

    // Blog approvals
    func blogApprovals(page: Int, q: String?) async throws -> Paged<BlogRow> { try await client.get("admin/blog-approvals", query: ["page": "\(page)", "q": q]) }
    func blogApproval(_ id: String) async throws -> BlogResponse { try await client.get("admin/blog-approvals/\(id.pathEncoded)") }
    func approveBlog(_ id: String) async throws -> ActionResponse { try await client.post("admin/blog-approvals/\(id.pathEncoded)/approve") }
    func rejectBlog(_ id: String) async throws -> ActionResponse { try await client.post("admin/blog-approvals/\(id.pathEncoded)/reject") }

    // Fatwa (admin)
    func fatwas(page: Int, q: String?, filter: String?) async throws -> Paged<FatwaRow> {
        try await client.get("admin/fatwa", query: ["page": "\(page)", "q": q, "filter": filter])
    }
    func fatwa(_ id: String) async throws -> FatwaAdminResponse { try await client.get("admin/fatwa/\(id.pathEncoded)") }
    func answerFatwa(_ id: String, _ form: FormBody) async throws -> ActionResponse { try await client.form("POST", "admin/fatwa/\(id.pathEncoded)/answer", form) }
    func rejectFatwa(_ id: String, _ form: FormBody) async throws -> ActionResponse { try await client.form("POST", "admin/fatwa/\(id.pathEncoded)/reject", form) }
    func deleteFatwa(_ id: String) async throws -> ActionResponse { try await client.delete("admin/fatwa/\(id.pathEncoded)") }

    // Digital library
    func library(page: Int, q: String?) async throws -> Paged<LibraryItemDto> { try await client.get("admin/library", query: ["page": "\(page)", "q": q]) }
    func libraryOptions() async throws -> LibraryOptions { try await client.get("admin/library", query: ["pageSize": "1"]) }
    func libraryItem(_ id: String) async throws -> LibraryResponse { try await client.get("admin/library/\(id.pathEncoded)") }
    func createLibraryItem(_ form: FormBody) async throws -> ActionResponse { try await client.form("POST", "admin/library", form) }
    func updateLibraryItem(_ id: String, _ form: FormBody) async throws -> ActionResponse { try await client.form("PATCH", "admin/library/\(id.pathEncoded)", form) }
    func deleteLibraryItem(_ id: String) async throws -> ActionResponse { try await client.delete("admin/library/\(id.pathEncoded)") }

    // Verse & hadith of the day
    func inspirations(page: Int, q: String?) async throws -> Paged<InspirationDto> { try await client.get("admin/daily-inspiration", query: ["page": "\(page)", "q": q]) }
    func inspiration(_ id: String) async throws -> InspirationAdminResponse { try await client.get("admin/daily-inspiration/\(id.pathEncoded)") }
    func createInspiration(_ form: FormBody) async throws -> ActionResponse { try await client.form("POST", "admin/daily-inspiration", form) }
    func updateInspiration(_ id: String, _ form: FormBody) async throws -> ActionResponse { try await client.form("PATCH", "admin/daily-inspiration/\(id.pathEncoded)", form) }
    func deleteInspiration(_ id: String) async throws -> ActionResponse { try await client.delete("admin/daily-inspiration/\(id.pathEncoded)") }

    // Teacher portal
    func teacherBlogs(page: Int) async throws -> Paged<BlogRow> { try await client.get("teacher/blogs", query: ["page": "\(page)"]) }
    func teacherBlogLimits() async throws -> ContentLimits { try await client.get("teacher/blogs", query: ["pageSize": "1"]) }
    func teacherBlog(_ id: String) async throws -> BlogResponse { try await client.get("teacher/blogs/\(id.pathEncoded)") }
    func createTeacherBlog(_ form: FormBody) async throws -> ActionResponse { try await client.form("POST", "teacher/blogs", form) }
    func updateTeacherBlog(_ id: String, _ form: FormBody) async throws -> ActionResponse { try await client.form("PATCH", "teacher/blogs/\(id.pathEncoded)", form) }
    func deleteTeacherBlog(_ id: String) async throws -> ActionResponse { try await client.delete("teacher/blogs/\(id.pathEncoded)") }

    func teacherFatwas(page: Int, q: String?, filter: String?) async throws -> Paged<FatwaRow> {
        try await client.get("teacher/fatwa", query: ["page": "\(page)", "q": q, "filter": filter])
    }
    func teacherFatwa(_ id: String) async throws -> FatwaAdminResponse { try await client.get("teacher/fatwa/\(id.pathEncoded)") }
    func answerTeacherFatwa(_ id: String, _ form: FormBody) async throws -> ActionResponse { try await client.form("POST", "teacher/fatwa/\(id.pathEncoded)/answer", form) }
}
