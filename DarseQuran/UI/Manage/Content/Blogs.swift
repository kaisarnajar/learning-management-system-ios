import SwiftUI

// Stubs: the section port replaces each screen's body (keep its name and initializer). Android: ui/manage/content/Blogs.kt.

/// Who is editing a blog post: the admin, or a teacher writing their own (Android's BlogEditorMode).
enum BlogEditorMode: Hashable, Sendable { case admin, teacher }

struct BlogsListScreen: View {
    var body: some View { StubScreen(title: "Blogs") }
}

struct TeacherBlogsListScreen: View {
    var body: some View { StubScreen(title: "My blog posts") }
}

struct BlogEditorScreen: View {
    let mode: BlogEditorMode
    let id: String?

    var body: some View { StubScreen(title: id == nil ? "New blog post" : "Edit blog post") }
}

struct BlogApprovalsListScreen: View {
    var body: some View { StubScreen(title: "Blog approvals") }
}

struct BlogApprovalDetailScreen: View {
    let id: String

    var body: some View { StubScreen(title: "Blog approval") }
}
