import SwiftUI

struct ExploreScreen: View {
    var body: some View { StubScreen(title: "Explore", tab: true) }
}

struct BlogListScreen: View {
    var body: some View { StubScreen(title: "Blog") }
}

struct BlogPostScreen: View {
    let id: String
    var body: some View { StubScreen(title: "Blog") }
}

struct FatwaListScreen: View {
    var body: some View { StubScreen(title: "Fatwa") }
}

struct FatwaDetailScreen: View {
    let id: String
    var body: some View { StubScreen(title: "Fatwa") }
}

struct LibraryListScreen: View {
    var body: some View { StubScreen(title: "Library") }
}

struct LibraryItemScreen: View {
    let id: String
    var body: some View { StubScreen(title: "Library") }
}

struct AnnouncementsScreen: View {
    var body: some View { StubScreen(title: "Announcements") }
}

struct AnnouncementScreen: View {
    let id: String
    var body: some View { StubScreen(title: "Announcement") }
}

struct TeachersScreen: View {
    var body: some View { StubScreen(title: "Teachers") }
}

struct TeacherScreen: View {
    let id: String
    var body: some View { StubScreen(title: "Teacher") }
}
