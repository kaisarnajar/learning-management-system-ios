import SwiftUI

// Stubs: the section port replaces each screen's body (keep its name and initializer). Android: ui/manage/courses/CoursesAdmin.kt.

struct CoursesAdminListScreen: View {
    var body: some View { StubScreen(title: "Courses") }
}

struct CourseHubScreen: View {
    let portal: Portal
    let courseId: String

    var body: some View { StubScreen(title: "Course") }
}

struct CourseFormScreen: View {
    let id: String?

    var body: some View { StubScreen(title: id == nil ? "Add course" : "Edit course") }
}

struct CourseRosterScreen: View {
    let courseId: String

    var body: some View { StubScreen(title: "Students") }
}
