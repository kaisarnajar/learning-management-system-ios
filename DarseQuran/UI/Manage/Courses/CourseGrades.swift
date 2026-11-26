import SwiftUI

// Stubs: the section port replaces each screen's body (keep its name and initializer). Android: ui/manage/courses/CourseGrades.kt.

struct GradeListScreen: View {
    let portal: Portal
    let courseId: String

    var body: some View { StubScreen(title: "Grade cards") }
}

struct GradeFormScreen: View {
    let portal: Portal
    let courseId: String
    let gradeId: String?

    var body: some View { StubScreen(title: gradeId == nil ? "Add test report" : "Edit grade card") }
}

struct StudentGradesScreen: View {
    let portal: Portal
    let courseId: String
    let enrollmentId: String

    var body: some View { StubScreen(title: "Grade report") }
}
