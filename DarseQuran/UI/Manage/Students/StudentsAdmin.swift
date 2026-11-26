import SwiftUI

// Stubs: the section port replaces each screen's body (keep its name and initializer). Android: ui/manage/students/StudentsAdmin.kt.

struct StudentsListScreen: View {
    var body: some View { StubScreen(title: "Students") }
}

struct StudentDetailScreen: View {
    let id: String

    var body: some View { StubScreen(title: "Student") }
}

struct StudentEditScreen: View {
    let id: String

    var body: some View { StubScreen(title: "Edit student") }
}
