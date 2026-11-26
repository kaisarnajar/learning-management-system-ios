import SwiftUI

// Stubs: the section port replaces each screen's body (keep its name and initializer). Android: ui/manage/courses/CourseAnnouncements.kt.

struct CourseAnnouncementsScreen: View {
    let portal: Portal
    let courseId: String
    let enrollmentId: String?
    let studentName: String?

    var body: some View { StubScreen(title: enrollmentId != nil ? "Messages" : "Announcements") }
}

struct AnnouncementFormScreen: View {
    let portal: Portal
    let courseId: String
    let enrollmentId: String?
    let announcementId: String?
    let studentName: String?

    var body: some View { StubScreen(title: announcementId != nil ? (enrollmentId != nil ? "Edit message" : "Edit announcement") : (enrollmentId != nil ? "Message for \(studentName ?? "student")" : "New announcement")) }
}
