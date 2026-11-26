import SwiftUI

struct CoursesScreen: View {
    var body: some View { StubScreen(title: "Courses", tab: true) }
}

struct CourseDetailScreen: View {
    let courseId: String
    var body: some View { StubScreen(title: "Course") }
}
