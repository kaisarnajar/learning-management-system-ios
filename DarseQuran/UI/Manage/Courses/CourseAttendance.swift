import SwiftUI

// Stubs: the section port replaces each screen's body (keep its name and initializer). Android: ui/manage/courses/CourseAttendance.kt.

struct AttendanceListScreen: View {
    let portal: Portal
    let courseId: String

    var body: some View { StubScreen(title: "Attendance") }
}

struct AttendanceTakeScreen: View {
    let portal: Portal
    let courseId: String
    let date: String?

    var body: some View { StubScreen(title: date == nil ? "Mark attendance" : "Edit attendance") }
}

struct AttendanceDayScreen: View {
    let portal: Portal
    let courseId: String
    let date: String

    var body: some View { StubScreen(title: "Attendance record") }
}

struct StudentAttendanceScreen: View {
    let portal: Portal
    let courseId: String
    let enrollmentId: String

    var body: some View { StubScreen(title: "Attendance report") }
}
