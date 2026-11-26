import SwiftUI

// Stubs: the section port replaces each screen's body (keep its name and initializer). Android: ui/manage/people/Teachers.kt.

struct TeachersListScreen: View {
    var body: some View { StubScreen(title: "Teachers") }
}

struct TeacherDetailScreen: View {
    let id: String

    var body: some View { StubScreen(title: "Teacher profile") }
}

struct TeacherFormScreen: View {
    let id: String?

    var body: some View { StubScreen(title: id == nil ? "Add teacher" : "Edit teacher") }
}
