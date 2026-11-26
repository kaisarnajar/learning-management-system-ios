import Observation
import SwiftUI

/*
 * The teacher portal (website: /teacher, /teacher/courses/[id], …/students/[enrollmentId]), ported from Android's
 * ui/teach/TeachHome.kt. A course's attendance, grade cards and announcements are the shared course tools in
 * UI/Manage/Courses, opened with Portal.teacher; the teacher's fatwa questions and blog posts are the content screens
 * (`.manage(.teacherFatwa)`, `.manage(.teacherBlogs)`).
 */

// MARK: - home (/teacher)

/// The teacher's name and counts, from the first page's response.
@MainActor
@Observable
final class TeachHeader {
    var home: TeacherHome?
}

/// The Teach tab's state: the first page of courses and the welcome header come in one response (one request, not
/// the same one twice).
@MainActor
final class TeachHomeModel {
    let header: TeachHeader
    let courses: PagedListModel<TeacherCourseRow>

    init(app: AppContainer) {
        let header = TeachHeader()
        self.header = header
        courses = PagedListModel(app: app) { app, page, _, _ in
            let api = app.service(TeachAPI.self)
            if page == 1 {
                let home = try await api.home()
                header.home = home
                return Paged(data: home.data, totalCount: home.totalCount, page: 1, pageSize: home.data.count)
            }
            return try await api.courses(page: page)
        }
    }
}

/// The teacher's tab: welcome and counts, shortcuts to their fatwa questions and blog posts, then their courses.
struct TeachHomeScreen: View {
    var body: some View {
        WithModel({ TeachHomeModel(app: $0) }) { model in TeachHomeContent(model: model) }
    }
}

private struct TeachHomeContent: View {
    let model: TeachHomeModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        ManageListScreen(
            "Teach", tab: true, model: model.courses, key: \.id,
            emptyTitle: "No courses are assigned to you yet. Contact the academy admin.", searchHint: nil,
            header: { header }
        ) { c in
            TeachCourseCard(course: c) { nav.push(.manage(.courseHub(portal: .teacher, courseId: c.id))) }
        }
        .reloadOnReturn { model.courses.refresh() }
    }

    @ViewBuilder private var header: some View {
        if let h = model.header.home {
            DetailCard {
                Text("Welcome back").textStyle(Typo.labelLarge).foregroundStyle(Scheme.primary)
                Text(h.teacher.name).textStyle(Typo.headlineSmall).foregroundStyle(Scheme.onSurface)
                if !h.teacher.specialization.trimmed.isEmpty {
                    Text(h.teacher.specialization).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
                }
                HStack(spacing: 10) {
                    StatTile("Courses", "\(h.stats.totalCourses)")
                    StatTile("Students", "\(h.stats.totalStudents)")
                }
                Field("Login email", h.teacher.email)
            }
        }
        HStack(spacing: 10) {
            ShortcutTile(label: "Fatwa questions", icon: .questionAnswer) { nav.push(.manage(.teacherFatwa)) }
            ShortcutTile(label: "Blog posts", icon: .edit) { nav.push(.manage(.teacherBlogs)) }
        }
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 8)
            Text("Your courses").textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface).accessibilityAddTraits(.isHeader)
            Text("View students, mark attendance, add grade cards and post announcements.")
                .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One of the teacher's courses.
private struct TeachCourseCard: View {
    let course: TeacherCourseRow
    let onClick: () -> Void

    var body: some View {
        let c = course
        AppCard(onClick: onClick) {
            HStack(spacing: 8) {
                StatusChip(c.statusLabel, tone: courseStatusTone(c.status))
                StatusChip(c.level, tone: .neutral)
            }
            Spacer().frame(height: 8)
            Text(c.title).textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface).multilineTextAlignment(.leading)
            Text("\(c.category) · Starts \(c.startDate ?? "—")").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
            if let duration = c.duration, !duration.trimmed.isEmpty {
                Text("Duration: \(duration)").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
            }
            if !c.description.trimmed.isEmpty {
                Spacer().frame(height: 4)
                Text(c.description).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant).lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer().frame(height: 6)
            Text("\(c.studentCount) student\(c.studentCount == 1 ? "" : "s") enrolled").textStyle(Typo.labelLarge).foregroundStyle(Scheme.onSurface)
        }
    }
}

private struct ShortcutTile: View {
    let label: String
    let icon: Icon
    let onClick: () -> Void

    var body: some View {
        AppCard(onClick: onClick) {
            RowIcon(icon)
            Spacer().frame(height: 8)
            Text(label).textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurface)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - students (/teacher/courses/[id])

/// The students of one of the teacher's courses.
struct TeacherStudentsScreen: View {
    let courseId: String

    var body: some View {
        WithModel({ app in
            PagedListModel<RosterRow>(app: app) { app, page, _, _ in try await app.service(TeachAPI.self).students(courseId, page: page) }
        }) { model in TeacherStudentsContent(courseId: courseId, model: model) }
    }
}

private struct TeacherStudentsContent: View {
    let courseId: String
    let model: PagedListModel<RosterRow>
    @Environment(Navigator.self) private var nav

    var body: some View {
        let total = model.state.total
        ManageListScreen(
            "Students", model: model, key: \.enrollmentId, emptyTitle: "No students enrolled in this course yet", searchHint: nil,
            header: {
                Text("\(total) student\(total == 1 ? "" : "s") enrolled").textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        ) { s in
            RecordCard(
                title: s.name ?? s.email,
                subtitle: "Roll no \(s.rollNumberLabel)",
                chip: s.status.map { status in (s.statusLabel ?? statusLabel(status).0, statusLabel(status).1) },
                onClick: { nav.push(.manage(.teacherStudent(courseId: courseId, enrollmentId: s.enrollmentId))) },
                leading: { RowIcon(.groups) }
            )
        }
        .reloadOnReturn { model.refresh() }
    }
}

// MARK: - one student (/teacher/courses/[id]/students/[enrollmentId])

/// A student of the teacher's course: their enrolment and profile, with Message, Attendance and Grades.
struct TeacherStudentScreen: View {
    let courseId: String
    let enrollmentId: String

    var body: some View {
        WithModel({ app in
            Loader(app: app) { try await $0.service(TeachAPI.self).student(courseId, enrollmentId: enrollmentId) }
        }) { loader in TeacherStudentContent(courseId: courseId, enrollmentId: enrollmentId, loader: loader) }
    }
}

private struct TeacherStudentContent: View {
    let courseId: String
    let enrollmentId: String
    let loader: Loader<TeacherStudentResponse>
    @Environment(Navigator.self) private var nav

    var body: some View {
        ManageScaffold("Student profile") {
            LoadedColumn(loader) { d in
                let s = d.student
                DetailCard {
                    Text(s.name).textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface)
                    Text(s.email).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                    HStack(spacing: 8) {
                        PillOutlinedButton("Message", icon: .mail) {
                            nav.push(.manage(.courseAnnouncements(portal: .teacher, courseId: courseId, enrollmentId: enrollmentId, studentName: s.name)))
                        }
                    }
                    HStack(spacing: 8) {
                        PillOutlinedButton("Attendance", icon: .eventAvailable) {
                            nav.push(.manage(.studentAttendance(portal: .teacher, courseId: courseId, enrollmentId: enrollmentId)))
                        }
                        PillOutlinedButton("Grades", icon: .grading) {
                            nav.push(.manage(.studentGrades(portal: .teacher, courseId: courseId, enrollmentId: enrollmentId)))
                        }
                    }
                }
                DetailCard("Enrollment in \(d.course.title)") {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Status").textStyle(Typo.labelMedium).foregroundStyle(Scheme.onSurfaceVariant)
                        StatusChip(d.enrollment.statusLabel, tone: statusLabel(d.enrollment.status).1)
                    }
                    Field("Roll no", d.enrollment.rollNumberLabel)
                    Field("Enrolled", formatDate(d.enrollment.createdAt))
                    Field("Completed", d.enrollment.completedAt.map { formatDate($0) })
                }
                DetailCard("Contact & profile") {
                    Field("Name", s.name)
                    Field("Father's name", s.fatherName)
                    Field("Date of birth", s.dateOfBirthDisplay)
                    Field("Occupation", s.occupationLabel)
                    Field("Address", s.address)
                    Field("WhatsApp", s.whatsapp)
                    Field("Email", s.email)
                    Field("Joined", formatDate(s.createdAt))
                }
            }
        }
        .reloadOnReturn { loader.reload() }
    }
}
